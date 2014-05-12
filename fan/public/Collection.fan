
** Represents a MongoDB collection.
const class Collection {
	
	private const Namespace	namespace
	
	internal const ConnectionManager conMgr

	** The qualified name of the collection. 
	** It takes the form of: 
	** 
	**   <database>.<collection>
	Str qname {
		get { namespace.qname }
		private set { }
	}

	** The simple name of the collection.
	Str name {
		get { namespace.collectionName }
		private set { }
	}
	
	new makeFromQname(ConnectionManager conMgr, Str qname) {
		this.conMgr		= conMgr
		this.namespace 	= Namespace(qname)
	}

	internal new makeFromNamespace(ConnectionManager conMgr, Namespace namespace) {
		this.conMgr		= conMgr
		this.namespace 	= namespace
	}

	new makeFromDatabase(Database database, Str name) {
		this.conMgr 	= database.conMgr
		this.namespace 	= Namespace(database.name, name)
	}

	** Returns 'true' if this collection exists.
	Bool exists() {
		Collection(conMgr, namespace.withCollection("system.namespaces")).findCount(["name": "${namespace.databaseName}.${name}"]) > 0
	}
	
	** Creates a new collection explicitly.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/create/`
	This create(Bool? autoIndexId := true, Bool? usePowerOf2Sizes := true) {
		cmd := cmd("insert").add("create", name)
		if (autoIndexId != null)
			cmd.add("autoIndexId", autoIndexId)
		if (usePowerOf2Sizes != null)
			cmd.add("flags", usePowerOf2Sizes ? 1 : 0)
		cmd.run
		// as create() only returns [ok:1.0], return this
		return this
	}

	Void createCapped(Int size, Int? maxNoOfDocs := null, Bool? autoIndexId := null, Bool? usePowerOf2Sizes := null) {
		// FIXME!
		// TODO: what it returns?
	}
	
	** Creates a `Cursor` over the given 'query' allowing you to iterate over results.
	** 
	** Returns what is returned from the given cursor function.
	** 
	** pre>
	** second := collection.find([:]) |cursor| {
	**     first  := cursor.next
	**     second := cursor.next
	**     return second
	** }
	** <pre
	** 
	** @see `Cursor`
	Obj? find(Str:Obj? query, |Cursor->Obj?| func) {
		conMgr.leaseConnection |con->Obj?| {
			cursor := Cursor(con, namespace, query)
			try {
				return func(cursor)
			} finally {
				cursor.kill
			}
		}
	}

	** An (optomised) method to return one document from the given 'query'.
	** 
	** Throws 'MongoErr' if no documents are found and 'checked' is true, returns 'null' otherwise.
	** Always throws 'MongoErr' if the query returns more than one document. 
	[Str:Obj?]? findOne(Str:Obj? query, Bool checked := true) {
		// findOne() is optomised to NOT call count() on a successful call 
		find(query) |cursor| {
			// "If numberToReturn is 1 the server will treat it as -1 (closing the cursor automatically)."
			// Means I can't use the isAlive() trick to check for more documents.
			cursor.batchSize = 2
			one := cursor.next(false) ?: (checked ? throw MongoErr(ErrMsgs.collection_findOneIsEmpty(qname, query)) : null)
			if (cursor.isAlive || cursor.next(false) != null)
				throw MongoErr(ErrMsgs.collection_findOneHasMany(qname, cursor.count, query))
			return one
		}
	}

	** Returns the result of the given 'query' as a list of documents.
	** 
	** @see `Cursor`
	[Str:Obj?][] findAll(Str:Obj? query := [:], Int skip := 0, Int? limit := null) {
		find(query) |Cursor cursor->[Str:Obj?][]| {
			cursor.skip  = skip
			cursor.limit = limit
			return cursor.toList
		}
	}

	** Returns the number of documents that would be returned by the given 'query'.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/count/`
	Int findCount(Str:Obj? query) {
		find(query) { it.count }
	}

	** Returns the number of documents in the collection.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/count/`
	Int size() {
		cmd("read", false).add("count", name).run["n"]->toInt
	}

	** Inserts the given document,
	** Returns the number of documents deleted.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/insert/`
	Int insert(Str:Obj? document) {
		insertMulti([document], null)["n"]->toInt
	}

	** Inserts many documents.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/insert/`
	@NoDoc
	Str:Obj? insertMulti([Str:Obj?][] inserts, Bool? ordered := null, [Str:Obj?]? writeConcern := null) {
		cmd := cmd("insert")
			.add("insert",		name)
			.add("documents",	inserts)
		if (ordered != null)		cmd["ordered"] 		= ordered
		if (writeConcern != null)	cmd["writeConcern"] = writeConcern
		return cmd.run
	}

	** Deletes documents that match the given query.
	** Returns the number of documents deleted.
	** 
	** If 'deleteAll' is 'true' then all documents matching the query will be deleted, otherwise 
	** only the first match will be deleted.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/delete/`
	Int delete(Str:Obj? query, Bool deleteAll := false) {
		cmd := [Str:Obj?][:] { ordered = true }
			.add("q",		query)
			.add("limit",	deleteAll ? 0 : 1)
		return deleteMulti([cmd], null)["n"]->toInt
	}

	** Executes many delete queries.
	** 	
	** @see `http://docs.mongodb.org/manual/reference/command/delete/`
	@NoDoc
	Str:Obj? deleteMulti([Str:Obj?][] deletes, Bool? ordered := null, [Str:Obj?]? writeConcern := null) {
		cmd := cmd("drop")
			.add("delete",	name)
			.add("deletes",	deletes)
		if (ordered != null)		cmd["ordered"] 		= ordered
		if (writeConcern != null)	cmd["writeConcern"] = writeConcern
		return cmd.run
	}

	** Runs the given 'updateCmd' against documents returned by the given 'query'.
	** Returns the number of documents modified.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/update/`
	// TODO: we loose any returned upserted id...?
	Int update(Str:Obj? query, Str:Obj? updateCmd, Bool? multi := false, Bool? upsert := false) {
		cmd := [Str:Obj?][:] { ordered = true }
			.add("q",	query)
			.add("u",	updateCmd)
		if (upsert != null)	cmd["upsert"] = upsert
		if (multi  != null)	cmd["multi"]  = multi
		return updateMulti([cmd], null)["nModified"]->toInt
	}

	** Runs multiple update queries.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/update/`
	@NoDoc
	Str:Obj? updateMulti([Str:Obj?][] updates, Bool? ordered := null, [Str:Obj?]? writeConcern := null) {
		cmd := cmd("update")
			.add("update",	name)
			.add("updates",	updates)
		if (ordered != null)		cmd["ordered"] 		= ordered
		if (writeConcern != null)	cmd["writeConcern"] = writeConcern
		return cmd.run
	}

//	http://docs.mongodb.org/manual/reference/command/findAndModify/#dbcmd.findAndModify
	// TODO: findAndDelete findAndUpdate
//	findAndDelete()
//	findAndUpdate()
	
	** Drops this collection.
	** 
	** @see `http://docs.mongodb.org/manual/reference/command/drop/`
	This drop() {
		// FIXME: check any returned output, can we check for errs?
		cmd("drop", false).add("drop", name).run
		// [ns:afMongoTest.col-test, nIndexesWas:1, ok:1.0] 
		// not sure wot 'nIndexesWas' or if it's useful, so return this for now 
		return this
	}
	
	Indexes indexes() {
		Indexes(conMgr, namespace)
	}
	
	// ---- Private Methods -----------------------------------------------------------------------
	
	private Cmd cmd(Str action, Bool checkForErrs := true) {
		Cmd(conMgr, namespace, action, checkForErrs)
	}	
}