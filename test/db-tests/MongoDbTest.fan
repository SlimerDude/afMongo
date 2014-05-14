using concurrent

internal class MongoDbTest : MongoTest {
	
	MongoClient? mc
	Database?	 db
	
	override Void setup() {
		mc = MongoClient(ActorPool())
		db = mc["afMongoTest"]
		// not dropping the DB makes the test x10 faster!
		db.collectionNames.each { db[it].drop }
		Pod.of(this).log.level = LogLevel.warn
	}

	override Void teardown() {
		mc?.shutdown
	}
	
}
