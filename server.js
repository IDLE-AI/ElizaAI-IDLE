import express from "express";
import multer from "multer";
import cors from "cors";
import { fileURLToPath } from "url";
import { dirname } from "path";
import fs from "fs/promises";
import pdf2md from "@opendocsg/pdf2md";
import fetch from "node-fetch";
import path from "path";
import util from "util";
import { join } from "path";
import { exec } from "child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const ELIZA_DIR = join(process.env.HOME, "/eliza-idle/eliza");
const CHARACTER_DIR = path.join(
  process.env.HOME,
  "eliza-idle",
  "eliza",
  "characters"
);

const app = express();

// CORS configuration with explicit methods
const corsOptions = {
  origin: true,
  credentials: true,
  methods: ["GET", "POST", "OPTIONS"],
  allowedHeaders: ["Content-Type", "X-API-Key", "Authorization"],
};

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: "uploads/",
  filename: (_, file, cb) => cb(null, file.originalname),
});

const upload = multer({ storage: storage });

// Middleware order is important
app.use(cors(corsOptions));
app.use(express.static(__dirname));
app.use(express.json({ limit: "50mb" })); // Move this up before routes

// Add OPTIONS handler for preflight requests
app.options("*", cors(corsOptions));

// Ensure uploads directory exists
await fs.mkdir("uploads", { recursive: true }).catch(console.error);

const getLatestCharacterFile = async () => {
  try {
    const files = await fs.readdir(CHARACTER_DIR);
    const jsonFiles = files.filter((file) => file.endsWith(".json"));

    if (jsonFiles.length === 0) return null;

    const fileStats = await Promise.all(
      jsonFiles.map(async (file) => ({
        name: file,
        stats: await fs.stat(path.join(CHARACTER_DIR, file)),
      }))
    );

    const latestFile = fileStats.sort(
      (a, b) => b.stats.mtime.getTime() - a.stats.mtime.getTime()
    )[0];
    return latestFile ? path.join(CHARACTER_DIR, latestFile.name) : null;
  } catch (err) {
    console.error("Error getting latest character file:", err);
    return null;
  }
};

app.post("/save-json", async (req, res) => {
  try {
    const characterData = req.body;
    console.log("Received character data:", characterData);
    const filePath = path.join(
      CHARACTER_DIR,
      `${characterData.name || "character"}.character.json`
    );

    console.log("Ensuring CHARACTER_DIR exists:", CHARACTER_DIR);
    await fs.mkdir(CHARACTER_DIR, { recursive: true });
    console.log("CHARACTER_DIR ensured:", CHARACTER_DIR);

    console.log("Saving JSON to:", filePath);
    await fs.writeFile(filePath, JSON.stringify(characterData, null, 2));
    console.log("JSON saved successfully to:", filePath);

    res.json({
      message: "JSON saved successfully!",
      filePath: filePath,
    });
  } catch (err) {
    console.error("Error saving JSON:", err);
    res.status(500).send("Failed to save JSON.");
  }
});

// Helper function to parse AI response
const parseAIResponse = (content) => {
  console.log("Original content:", content);

  try {
    // First try direct JSON parse
    return JSON.parse(content);
  } catch (directParseError) {
    console.log("Direct parse failed, attempting cleanup");

    // Find the JSON object boundaries
    const startIndex = content.indexOf("{");
    const endIndex = content.lastIndexOf("}");

    if (startIndex === -1 || endIndex === -1) {
      throw new Error("No complete JSON object found in response");
    }

    let jsonContent = content.substring(startIndex, endIndex + 1);

    // Clean up common issues
    jsonContent = jsonContent
      .replace(/,\s*}/g, "}") // Remove trailing commas
      .replace(/,\s*]/g, "]") // Remove trailing commas in arrays
      .replace(/\{\s*\}/g, "{}") // Normalize empty objects
      .replace(/\[\s*\]/g, "[]") // Normalize empty arrays
      .replace(/"\s*:\s*undefined/g, '": null') // Replace undefined with null
      .replace(/"\s*:\s*,/g, '": null,') // Fix empty values
      .replace(/"\s*:\s*}/g, '": null}') // Fix empty values at end
      .replace(/\n/g, " ") // Remove newlines
      .replace(/\s+/g, " ") // Normalize whitespace
      .trim();

    console.log("Cleaned JSON content:", jsonContent);

    try {
      return JSON.parse(jsonContent);
    } catch (cleanupParseError) {
      console.error("Parse error after cleanup:", cleanupParseError);
      throw new Error(
        `Failed to parse JSON content: ${cleanupParseError.message}`
      );
    }
  }
};

// Fix JSON formatting endpoint
app.post("/api/fix-json", async (req, res) => {
  try {
    const { content } = req.body;

    if (!content) {
      return res.status(400).json({ error: "Content is required" });
    }

    console.log("Original content:", content);

    try {
      const characterData = parseAIResponse(content);
      console.log("Successfully parsed character data");
      res.json({ character: characterData });
    } catch (parseError) {
      console.error("Parse error:", parseError);
      console.error("Content:", content);
      throw new Error(`Failed to parse JSON: ${parseError.message}`);
    }
  } catch (error) {
    console.error("JSON fixing error:", error);
    res
      .status(500)
      .json({ error: error.message || "Failed to fix JSON formatting" });
  }
});

// Add this helper function near the top
const sendJsonResponse = (res, data) => {
  res.setHeader("Content-Type", "application/json");
  return res.json(data);
};

// Character generation endpoint
app.post("/api/generate-prompt-character", async (req, res) => {
  try {
    const { prompt, model } = req.body;
    const apiKey = req.headers["x-api-key"];

    // Validate inputs
    if (!prompt) {
      return sendJsonResponse(res.status(400), { error: "Prompt is required" });
    }
    if (!model) {
      return sendJsonResponse(res.status(400), { error: "Model is required" });
    }
    if (!apiKey) {
      return sendJsonResponse(res.status(400), {
        error: "API key is required",
      });
    }

    // Extract potential name from the prompt
    const nameMatch = prompt.match(
      /name(?:\s+is)?(?:\s*:)?\s*([A-Z][a-zA-Z\s]+?)(?:\.|\s|$)/i
    );
    const suggestedName = nameMatch ? nameMatch[1].trim() : "";

    // Create a template for consistent structure
    const template = {
      name: suggestedName,
      clients: [],
      modelProvider: "",
      settings: {
        secrets: {}, // Changed from empty object to properly nested structure
        voice: {
          model: "",
        },
      },
      plugins: [],
      bio: [],
      lore: [],
      knowledge: [],
      messageExamples: [],
      postExamples: [],
      topics: [],
      style: {
        all: [],
        chat: [],
        post: [],
      },
      adjectives: [],
      people: [],
    };

    const response = await fetch(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": process.env.APP_URL || "http://localhost:4000",
          "X-Title": "Eliza Character Generator",
        },
        body: JSON.stringify({
          model: model,
          messages: [
            {
              role: "system",
              content: `You are a character generation assistant that MUST ONLY output valid JSON. NEVER output apologies, explanations, or any other text.

CRITICAL RULES:
1. ONLY output a JSON object following the exact template structure provided
2. Start with { and end with }
3. NO text before or after the JSON
4. NO apologies or explanations
5. NO content warnings or disclaimers
6. Every sentence must end with a period
7. Adjectives must be single words
8. Knowledge entries MUST be an array of strings, each ending with a period
9. Each knowledge entry MUST be a complete sentence
10. Use the suggested name if provided, or generate an appropriate one

You will receive a character description and template. Generate a complete character profile.`,
            },
            {
              role: "user",
              content: `Template to follow:
${JSON.stringify(template, null, 2)}

Character description: ${prompt}

Generate a complete character profile as a single JSON object following the exact template structure. Include relevant knowledge entries based on the description.`,
            },
          ],
          temperature: 0.7,
          max_tokens: 4000,
          presence_penalty: 0.0,
          frequency_penalty: 0.0,
          top_p: 0.95,
          stop: null,
        }),
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || "Failed to generate character");
    }

    const data = await response.json();
    const generatedContent = data.choices[0].message.content;

    try {
      console.log("Raw AI response:", generatedContent);
      const characterData = parseAIResponse(generatedContent);
      console.log("Parsed character:", characterData);

      // Ensure all required fields are present
      const requiredFields = [
        "bio",
        "lore",
        "topics",
        "style",
        "adjectives",
        "messageExamples",
        "postExamples",
      ];
      const missingFields = requiredFields.filter(
        (field) => !characterData[field]
      );

      if (missingFields.length > 0) {
        throw new Error(
          `Invalid character data: missing ${missingFields.join(", ")}`
        );
      }

      // Process knowledge entries specifically
      if (characterData.knowledge) {
        characterData.knowledge = Array.isArray(characterData.knowledge)
          ? characterData.knowledge.map((entry) => {
              if (typeof entry === "string") {
                return entry.endsWith(".") ? entry : entry + ".";
              }
              if (typeof entry === "object" && entry !== null) {
                // If it's an object, try to extract meaningful text
                const text =
                  entry.text ||
                  entry.content ||
                  entry.value ||
                  entry.toString();
                return typeof text === "string"
                  ? text.endsWith(".")
                    ? text
                    : text + "."
                  : "Invalid knowledge entry.";
              }
              return "Invalid knowledge entry.";
            })
          : [];
      } else {
        characterData.knowledge = [];
      }

      // Ensure all other arrays are properly initialized
      characterData.bio = Array.isArray(characterData.bio)
        ? characterData.bio
        : [];
      characterData.lore = Array.isArray(characterData.lore)
        ? characterData.lore
        : [];
      characterData.topics = Array.isArray(characterData.topics)
        ? characterData.topics
        : [];
      characterData.messageExamples = Array.isArray(
        characterData.messageExamples
      )
        ? characterData.messageExamples
        : [];
      characterData.postExamples = Array.isArray(characterData.postExamples)
        ? characterData.postExamples
        : [];
      characterData.adjectives = Array.isArray(characterData.adjectives)
        ? characterData.adjectives
        : [];
      characterData.people = Array.isArray(characterData.people)
        ? characterData.people
        : [];
      characterData.style = characterData.style || {
        all: [],
        chat: [],
        post: [],
      };

      // Ensure style arrays are properly initialized
      characterData.style.all = Array.isArray(characterData.style.all)
        ? characterData.style.all
        : [];
      characterData.style.chat = Array.isArray(characterData.style.chat)
        ? characterData.style.chat
        : [];
      characterData.style.post = Array.isArray(characterData.style.post)
        ? characterData.style.post
        : [];

      return sendJsonResponse(res, {
        character: characterData,
        rawPrompt: prompt,
        rawResponse: generatedContent,
      });
    } catch (parseError) {
      console.error("Parse error:", parseError);
      console.error("Generated content:", generatedContent);
      throw new Error(
        `Failed to parse generated content: ${parseError.message}`
      );
    }
  } catch (error) {
    console.error("Character generation error:", error);
    return sendJsonResponse(res.status(500), {
      error: error.message || "Failed to generate character",
    });
  }
});

// File processing endpoint
app.post("/api/process-files", upload.array("files"), async (req, res) => {
  try {
    const files = req.files;
    if (!files || files.length === 0) {
      return res.status(400).json({ error: "No files uploaded" });
    }

    const knowledge = [];

    for (const file of files) {
      try {
        const content = await fs.readFile(file.path);
        let processedContent;

        if (file.mimetype === "application/pdf") {
          const uint8Array = new Uint8Array(content);
          processedContent = await pdf2md(uint8Array);
          processedContent = processedContent
            .split(/[.!?]+/)
            .map((sentence) => sentence.trim())
            .filter(
              (sentence) => sentence.length > 0 && !sentence.startsWith("-")
            )
            .map((sentence) => sentence + ".");
        } else if (isTextFile(file.originalname)) {
          processedContent = content
            .toString("utf-8")
            .split(/[.!?]+/)
            .map((sentence) => sentence.trim())
            .filter(
              (sentence) => sentence.length > 0 && !sentence.startsWith("-")
            )
            .map((sentence) => sentence + ".");
        }

        if (processedContent) {
          knowledge.push(...processedContent);
        }

        await fs.unlink(file.path).catch(console.error);
      } catch (fileError) {
        console.error(`Error processing file ${file.originalname}:`, fileError);
      }
    }

    res.json({ knowledge });
  } catch (error) {
    console.error("File processing error:", error);
    res.status(500).json({ error: "Failed to process files" });
  }
});

// Helper functions
const isTextFile = (filename) =>
  [".txt", ".md", ".json", ".yml", ".csv"].includes(
    filename.toLowerCase().slice(filename.lastIndexOf("."))
  );

// Add this new endpoint with the other API endpoints
app.post("/api/refine-character", async (req, res) => {
  try {
    const { prompt, model, currentCharacter } = req.body;
    const apiKey = req.headers["x-api-key"];

    if (!prompt || !model || !currentCharacter) {
      return res.status(400).json({
        error: "Prompt, model, and current character data are required",
      });
    }
    if (!apiKey) {
      return res.status(400).json({ error: "API key is required" });
    }

    // Store existing knowledge and name
    const hasExistingKnowledge =
      Array.isArray(currentCharacter.knowledge) &&
      currentCharacter.knowledge.length > 0;
    const existingKnowledge = currentCharacter.knowledge || [];
    const existingName = currentCharacter.name || "";

    // Extract potential new name from the prompt
    const nameMatch = prompt.match(
      /name(?:\s+is)?(?:\s*:)?\s*([A-Z][a-zA-Z\s]+?)(?:\.|\s|$)/i
    );
    const newName = nameMatch ? nameMatch[1].trim() : existingName;

    // Create a template for the AI to follow
    const template = {
      name: newName,
      clients: currentCharacter.clients || [],
      modelProvider: currentCharacter.modelProvider || "",
      settings: currentCharacter.settings || {
        secrets: {},
        voice: { model: "" },
      },
      plugins: currentCharacter.plugins || [],
      bio: [],
      lore: [],
      knowledge: hasExistingKnowledge ? existingKnowledge : [],
      messageExamples: [],
      postExamples: [],
      topics: [],
      style: {
        all: [],
        chat: [],
        post: [],
      },
      adjectives: [],
      people: currentCharacter.people || [],
    };

    const response = await fetch(
      "https://openrouter.ai/api/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
          "HTTP-Referer": process.env.APP_URL || "http://localhost:4000",
          "X-Title": "Eliza Character Generator",
        },
        body: JSON.stringify({
          model: model,
          messages: [
            {
              role: "system",
              content: `You are a character refinement assistant that MUST ONLY output valid JSON. NEVER output apologies, explanations, or any other text.

CRITICAL RULES:
1. ONLY output a JSON object following the exact template structure provided
2. Start with { and end with }
3. NO text before or after the JSON
4. NO apologies or explanations
5. NO content warnings or disclaimers
6. Maintain the character's core traits while incorporating refinements
7. Every sentence must end with a period
8. Adjectives must be single words
9. Knowledge entries MUST be an array of strings, each ending with a period
10. Each knowledge entry MUST be a complete sentence
11. Use the new name if provided in the refinement instructions

You will receive the current character data and refinement instructions. Enhance and modify the character while maintaining consistency.`,
            },
            {
              role: "user",
              content: `Current character data:
${JSON.stringify(currentCharacter, null, 2)}

Template to follow:
${JSON.stringify(template, null, 2)}

Refinement instructions: ${prompt}

Output the refined character data as a single JSON object following the exact template structure. ${
                hasExistingKnowledge
                  ? "DO NOT modify the existing knowledge array."
                  : "Create new knowledge entries if appropriate."
              }`,
            },
          ],
          temperature: 0.7,
          max_tokens: 4000,
          presence_penalty: 0.0,
          frequency_penalty: 0.0,
          top_p: 0.95,
          stop: null,
        }),
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || "Failed to refine character");
    }

    const data = await response.json();
    const refinedContent = data.choices[0].message.content;

    try {
      console.log("Raw AI response:", refinedContent);
      const refinedCharacter = parseAIResponse(refinedContent);
      console.log("Parsed character:", refinedCharacter);

      // Ensure all required fields are present
      const requiredFields = [
        "bio",
        "lore",
        "topics",
        "style",
        "adjectives",
        "messageExamples",
        "postExamples",
      ];
      const missingFields = requiredFields.filter(
        (field) => !refinedCharacter[field]
      );

      if (missingFields.length > 0) {
        throw new Error(
          `Invalid character data: missing ${missingFields.join(", ")}`
        );
      }

      // Process knowledge entries specifically
      if (refinedCharacter.knowledge) {
        refinedCharacter.knowledge = Array.isArray(refinedCharacter.knowledge)
          ? refinedCharacter.knowledge.map((entry) => {
              if (typeof entry === "string") {
                return entry.endsWith(".") ? entry : entry + ".";
              }
              if (typeof entry === "object" && entry !== null) {
                // If it's an object, try to extract meaningful text
                const text =
                  entry.text ||
                  entry.content ||
                  entry.value ||
                  entry.toString();
                return typeof text === "string"
                  ? text.endsWith(".")
                    ? text
                    : text + "."
                  : "Invalid knowledge entry.";
              }
              return "Invalid knowledge entry.";
            })
          : [];
      } else {
        refinedCharacter.knowledge = [];
      }

      // If there's existing knowledge, preserve it
      if (hasExistingKnowledge) {
        refinedCharacter.knowledge = existingKnowledge;
      }

      // Ensure all arrays are properly initialized
      refinedCharacter.bio = Array.isArray(refinedCharacter.bio)
        ? refinedCharacter.bio
        : [];
      refinedCharacter.lore = Array.isArray(refinedCharacter.lore)
        ? refinedCharacter.lore
        : [];
      refinedCharacter.topics = Array.isArray(refinedCharacter.topics)
        ? refinedCharacter.topics
        : [];
      refinedCharacter.messageExamples = Array.isArray(
        refinedCharacter.messageExamples
      )
        ? refinedCharacter.messageExamples
        : [];
      refinedCharacter.postExamples = Array.isArray(
        refinedCharacter.postExamples
      )
        ? refinedCharacter.postExamples
        : [];
      refinedCharacter.adjectives = Array.isArray(refinedCharacter.adjectives)
        ? refinedCharacter.adjectives
        : [];
      refinedCharacter.people = Array.isArray(refinedCharacter.people)
        ? refinedCharacter.people
        : [];
      refinedCharacter.style = refinedCharacter.style || {
        all: [],
        chat: [],
        post: [],
      };

      // Ensure style arrays are properly initialized
      refinedCharacter.style.all = Array.isArray(refinedCharacter.style.all)
        ? refinedCharacter.style.all
        : [];
      refinedCharacter.style.chat = Array.isArray(refinedCharacter.style.chat)
        ? refinedCharacter.style.chat
        : [];
      refinedCharacter.style.post = Array.isArray(refinedCharacter.style.post)
        ? refinedCharacter.style.post
        : [];

      res.json({
        character: refinedCharacter,
        rawPrompt: prompt,
        rawResponse: refinedContent,
      });
    } catch (parseError) {
      console.error("Parse error:", parseError);
      console.error("Refined content:", refinedContent);
      throw new Error(`Failed to parse refined content: ${parseError.message}`);
    }
  } catch (error) {
    console.error("Character refinement error:", error);
    res
      .status(500)
      .json({ error: error.message || "Failed to refine character" });
  }
});
let generatedCharacter = null;

app.post("/generate-character", async (req, res) => {
  const scriptPath = path.join(__dirname, "setup.sh");

  try {
    console.log("Retrieving latest character file...");
    let latestCharacterFile = await getLatestCharacterFile();

    if (!latestCharacterFile) {
      return res.status(400).json({ error: "No character files found" });
    }

    console.log("Using character file:", latestCharacterFile);
  } catch (error) {
    console.error("Error getting latest character file:", error);
    return res
      .status(500)
      .json({ error: "Failed to get latest character file" });
  }
  try {
    // Create necessary directories
    await fs.mkdir(CHARACTER_DIR, { recursive: true });

    // Make script executable and verify it exists
    await fs.access(scriptPath).catch(() => {
      throw new Error(`Setup script not found at: ${scriptPath}`);
    });

    await fs.chmod(scriptPath, "755");
    console.log("Script permissions set");

    const execPromise = util.promisify(exec);
    console.log("Executing script with command:", `bash "${scriptPath}" start`);

    let latestCharacterFile = await getLatestCharacterFile();
    const characterFileName = path.basename(latestCharacterFile);

    const { stdout, stderr } = await execPromise(
      `CHARACTER_FILE=${characterFileName} bash ${scriptPath} start | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'`,
      {
        cwd: __dirname,
        env: {
          ...process.env,
          HOME: process.env.HOME,
          PATH: `${process.env.PATH}:/usr/local/bin:/opt/homebrew/bin`,
          CHARACTER_FILE: characterFileName,
          FORCE_COLOR: "0",
          NO_COLOR: "1",
          CI: "true",
          DEBUG: "true",
        },
        timeout: 240000,
        maxBuffer: 1024 * 1024 * 50,
      }
    );

    if (stderr) {
      console.error("Script stderr:", stderr);
    }
    console.log("Script stdout:", stdout);

    if (
      !stdout.includes("Installation Complete") &&
      !stdout.includes("Project built successfully")
    ) {
      throw new Error("Script did not complete successfully");
    }

    const files = await fs.readdir(CHARACTER_DIR);
    console.log("Files in CHARACTER_DIR:", files);
    const characterFile = files.find((file) => file.endsWith(".json"));

    if (!characterFile) {
      console.error("No character file found in:", CHARACTER_DIR);
      return res.status(500).json({ error: "Character file not found" });
    }

    const characterFilePath = path.join(CHARACTER_DIR, characterFile);
    const characterJson = await fs.readFile(characterFilePath, "utf-8");

    let generatedCharacter;
    try {
      generatedCharacter = JSON.parse(characterJson);
    } catch (err) {
      console.error("Error parsing character JSON:", err);
      return res.status(500).json({ error: "Invalid character JSON format" });
    }
    res.json({
      message: "Character generated successfully!",
      stdout,
      character: generatedCharacter,
    });
  } catch (error) {
    console.error("Script execution error:", {
      message: error.message,
      stdout: error.stdout,
      stderr: error.stderr,
      code: error.code,
    });

    return res.status(500).json({
      error: "Script execution failed",
      details: error.message,
      stdout: error.stdout,
      stderr: error.stderr,
    });
  }
});

app.get("/api/get-generated-character", (req, res) => {
  if (generatedCharacter) {
    res.json({ character: generatedCharacter });
  } else {
    res.status(404).json({ error: "No character generated yet" });
  }
});
const PORT = process.env.PORT || 4001;
const HOST = process.env.HOST || "0.0.0.0";

app.listen(PORT, HOST, () => {
  console.log(`Server running on http://${HOST}:${PORT}`);
});

// Update the error handling middleware at the bottom
app.use((err, req, res, next) => {
  console.error("Server error:", err);
  return sendJsonResponse(res.status(500), {
    error: "Internal server error",
    details: err.message,
  });
});

// Add this catch-all middleware for unhandled routes
app.use((req, res) => {
  return sendJsonResponse(res.status(404), {
    error: "Not Found",
    path: req.path,
  });
});
