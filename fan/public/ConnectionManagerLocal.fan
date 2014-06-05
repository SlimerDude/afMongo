using afConcurrent

@NoDoc	// Should be internal, but it might prove useful.
const class ConnectionManagerLocal : ConnectionManager {
	private const LocalRef connectionRef	:= LocalRef("afMongo.connection")
	
	new make(Connection connection) {
		connectionRef.val = connection
	}
	
	override Obj? leaseConnection(|Connection->Obj?| c) {
		// TODO: throw Err if connection doesn't exist in this thread
		c(connectionRef.val)
	}
	
	override This startup() {
		return this
	}

	override This shutdown() {
		(connectionRef.val as Connection)?.close
		connectionRef.cleanUp
		return this
	}
}