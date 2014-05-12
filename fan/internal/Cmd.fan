
internal class Cmd {
	private const ConnectionManager conMgr
	private const Namespace			namespace

	private [Str:Obj?] 	cmd	:= Str:Obj?[:] { ordered = true }
	private [Str:Obj?]?	writeConcern
	private Bool 		checkForErrs
	private Str 		when
	private Str 		what
	
	new make(ConnectionManager conMgr, Namespace namespace, Str action, Bool checkForErrs, [Str:Obj?]? writeConcern := null) {
		this.conMgr			= conMgr
		this.namespace 		= namespace
		this.writeConcern	= writeConcern
		this.checkForErrs	= checkForErrs
		
		switch (action) {
			case "read":
				this.when	= "reading from"
				this.what	= "read"
				this.writeConcern = null
			case "insert":
				this.when	= "inserting into"
				this.what	= "inserted"
			case "update":
				this.when	= "updating"
				this.what	= "updated"
			case "drop":
				this.when	= "dropping from"
				this.what	= "dropped"
			default:
				throw ArgErr("Unknown action: $action")
		}
	}

	This add(Str key, Obj? val) {
		cmd[key] = val
		return this
	}	

	@Operator
	Obj? get(Str key) {
		cmd[key]
	}
	
	@Operator
	This set(Str key, Obj? val) {
		cmd[key] = val
		return this
	}	
	
	Str:Obj? run() {
		if (writeConcern != null && !cmd.containsKey("writeConcern"))
			cmd["writeConcern"] = writeConcern

		return checkForWriteErrs(conMgr.leaseConnection |con->Obj?| {
			Operation(con).runCommand("${namespace.databaseName}.\$cmd", cmd)			
		})
	}

	Str:Obj? runAdmin() {
		if (writeConcern != null && !cmd.containsKey("writeConcern"))
			cmd["writeConcern"] = writeConcern

		return checkForWriteErrs(conMgr.leaseConnection |con->Obj?| {
			Operation(con).runCommand("admin.\$cmd", cmd)
		})
	}
	
	private Str:Obj? checkForWriteErrs(Str:Obj? doc) {
		if (!checkForErrs) return doc

		errs := [Str:Obj?][,]
		if (doc.containsKey("writeErrors"))
			errs.addAll((Obj?[]) doc["writeErrors"])
		if (doc.containsKey("writeConcernError"))
			errs.add((Str:Obj?) doc["writeConcernError"])
		if (!errs.isEmpty)
			throw MongoCmdErr(ErrMsgs.collection_writeErrs(when, namespace.qname, errs))
		if (doc["n"]?->toInt == 0)
			// TODO: have a 'checked' variable?
			throw MongoErr(ErrMsgs.collection_nothingHappened(what, doc))
		return doc
	}
	
}