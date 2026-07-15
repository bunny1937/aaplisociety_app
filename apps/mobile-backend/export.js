
import { MongoClient } from "mongodb";
import fs from "fs";

const uri = "mongodb://aaplisociety2025:NoubN8xOvrLdxH2h@ac-zyx7wzy-shard-00-00.ttqpd0g.mongodb.net:27017,ac-zyx7wzy-shard-00-01.ttqpd0g.mongodb.net:27017,ac-zyx7wzy-shard-00-02.ttqpd0g.mongodb.net:27017/test?ssl=true&authSource=admin&replicaSet=atlas-ftyddp-shard-0&retryWrites=true&w=majority";

const client = new MongoClient(uri);

try {
  await client.connect();

  const db = client.db(); // database from URI
  const collections = await db.listCollections().toArray();

  if (!fs.existsSync("mongo_export")) {
    fs.mkdirSync("mongo_export");
  }

  for (const col of collections) {
    console.log(`Exporting ${col.name}...`);
    const docs = await db.collection(col.name).find({}).toArray();
    fs.writeFileSync(
      `mongo_export/${col.name}.json`,
      JSON.stringify(docs, null, 2)
    );
  }

  console.log("Done!");
} finally {
  await client.close();
}