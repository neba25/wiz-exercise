const express = require("express");
const { MongoClient } = require("mongodb");

const app = express();
app.use(express.json());
app.use(express.static("public"));

// Populated via a Kubernetes env var sourced from a Secret - satisfies
// "Access to MongoDB must be configured via an environment variable"
const MONGO_URI = process.env.MONGO_URI;
const PORT = process.env.PORT || 3000;

let db;

async function connectDb() {
  const client = new MongoClient(MONGO_URI);
  await client.connect();
  db = client.db("todoapp");
  console.log("Connected to MongoDB");
}

app.get("/healthz", (req, res) => res.status(200).send("ok"));

app.get("/api/todos", async (req, res) => {
  const todos = await db.collection("todos").find({}).toArray();
  res.json(todos);
});

app.post("/api/todos", async (req, res) => {
  const { text } = req.body;
  if (!text) return res.status(400).json({ error: "text is required" });
  const result = await db.collection("todos").insertOne({
    text,
    done: false,
    createdAt: new Date(),
  });
  res.status(201).json({ _id: result.insertedId, text, done: false });
});

app.put("/api/todos/:id/toggle", async (req, res) => {
  const { ObjectId } = require("mongodb");
  const todo = await db.collection("todos").findOne({ _id: new ObjectId(req.params.id) });
  if (!todo) return res.status(404).json({ error: "not found" });
  await db.collection("todos").updateOne(
    { _id: todo._id },
    { $set: { done: !todo.done } }
  );
  res.json({ ok: true });
});

connectDb()
  .then(() => {
    app.listen(PORT, () => console.log(`Listening on port ${PORT}`));
  })
  .catch((err) => {
    console.error("Failed to connect to MongoDB", err);
    process.exit(1);
  });
// pipeline test Thu Jul  9 20:00:41 EDT 2026
