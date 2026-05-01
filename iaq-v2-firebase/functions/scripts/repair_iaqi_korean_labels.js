const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {
    inputPath: null,
    referencePath: null,
    outputPath: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if ((token === "--input" || token === "-i") && argv[i + 1]) {
      args.inputPath = argv[i + 1].trim();
      i += 1;
      continue;
    }
    if ((token === "--reference" || token === "-r") && argv[i + 1]) {
      args.referencePath = argv[i + 1].trim();
      i += 1;
      continue;
    }
    if ((token === "--output" || token === "-o") && argv[i + 1]) {
      args.outputPath = argv[i + 1].trim();
      i += 1;
    }
  }

  return args;
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;

  const flushField = () => {
    row.push(field);
    field = "";
  };

  const flushRow = () => {
    rows.push(row);
    row = [];
  };

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];

    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < text.length && text[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
      continue;
    }

    if (ch === ",") {
      flushField();
      continue;
    }

    if (ch === "\n") {
      flushField();
      flushRow();
      continue;
    }

    if (ch === "\r") {
      continue;
    }

    field += ch;
  }

  const hasTail = field.length > 0 || row.length > 0;
  if (hasTail) {
    flushField();
    flushRow();
  }

  if (!rows.length) {
    return { headers: [], records: [] };
  }

  const headers = rows[0].map((header, index) => {
    if (index === 0) {
      return String(header).replace(/^\uFEFF/, "");
    }
    return header;
  });

  const records = rows.slice(1).map((cols) => {
    const rec = {};
    for (let i = 0; i < headers.length; i += 1) {
      rec[headers[i]] = i < cols.length ? cols[i] : "";
    }
    return rec;
  });

  return { headers, records };
}

function csvEscape(value) {
  const text = value == null ? "" : String(value);
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function toCsvText(rows, columns) {
  const lines = [columns.map(csvEscape).join(",")];
  for (const row of rows) {
    const values = columns.map((col) => csvEscape(row[col]));
    lines.push(values.join(","));
  }
  return lines.join("\n");
}

function toFiniteNumberOrNull(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === "string" && value.trim() === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeHistoryFlag(value) {
  return String(value || "").trim().toLowerCase() === "history";
}

function resolveLabelFromScores(mScore, eScore) {
  if (!Number.isFinite(mScore)) {
    return null;
  }

  if (mScore <= 0) {
    return { primary: "좋음", sub: "" };
  }

  if (mScore < 1) {
    return { primary: "보통", sub: "" };
  }

  let sub = "";
  if (Number.isFinite(eScore)) {
    if (eScore < 1) {
      sub = "경미한 악화 (나쁨-1)";
    } else if (eScore < 2) {
      sub = "중간수준 악화 (나쁨-2)";
    } else if (eScore < 3) {
      sub = "심각한 악화 (나쁨-3)";
    } else {
      sub = "매우 위험 (나쁨-4)";
    }
  }

  return { primary: "나쁨", sub };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.inputPath) {
    throw new Error("Missing --input <csvPath>");
  }

  const inputPath = path.resolve(args.inputPath);
  const referencePath = args.referencePath ? path.resolve(args.referencePath) : null;
  const outputPath = args.outputPath ? path.resolve(args.outputPath) : inputPath;

  if (!fs.existsSync(inputPath)) {
    throw new Error(`Input CSV not found: ${inputPath}`);
  }

  const inputText = fs.readFileSync(inputPath, "utf8");
  const { headers, records } = parseCsv(inputText);

  if (!records.length) {
    throw new Error("Input CSV has no data rows");
  }

  if (!headers.includes("timestamp") || !headers.includes("iaqi.primary_grade") || !headers.includes("iaqi.sub_level")) {
    throw new Error("Required columns missing in input CSV");
  }

  const referenceMap = new Map();
  if (referencePath && fs.existsSync(referencePath)) {
    const refText = fs.readFileSync(referencePath, "utf8");
    const { records: refRecords } = parseCsv(refText);

    for (const row of refRecords) {
      if (row.source_collection && !normalizeHistoryFlag(row.source_collection)) {
        continue;
      }
      const ts = String(row.timestamp || "").trim();
      if (!ts) continue;
      referenceMap.set(ts, {
        primary: String(row["iaqi.primary_grade"] || ""),
        sub: String(row["iaqi.sub_level"] || ""),
      });
    }
  }

  let changedPrimary = 0;
  let changedSub = 0;
  let restoredByReference = 0;
  let restoredByScores = 0;

  for (const row of records) {
    const ts = String(row.timestamp || "").trim();
    const mScore = toFiniteNumberOrNull(row["iaqi.m_score"]);
    const eScore = toFiniteNumberOrNull(row["iaqi.e_score"]);

    const fromScores = resolveLabelFromScores(mScore, eScore);
    const fromReference = referenceMap.get(ts) || null;

    let nextPrimary = row["iaqi.primary_grade"];
    let nextSub = row["iaqi.sub_level"];

    if (fromScores) {
      nextPrimary = fromScores.primary;
      if (mScore >= 1) {
        nextSub = fromScores.sub || (fromReference?.sub || "");
      } else {
        nextSub = "";
      }
      restoredByScores += 1;
    } else if (fromReference) {
      nextPrimary = fromReference.primary;
      nextSub = fromReference.sub;
      restoredByReference += 1;
    }

    if (String(row["iaqi.primary_grade"] || "") !== String(nextPrimary || "")) {
      row["iaqi.primary_grade"] = nextPrimary || "";
      changedPrimary += 1;
    }

    if (String(row["iaqi.sub_level"] || "") !== String(nextSub || "")) {
      row["iaqi.sub_level"] = nextSub || "";
      changedSub += 1;
    }
  }

  const outText = toCsvText(records, headers);
  fs.writeFileSync(outputPath, outText, "utf8");

  console.log("INPUT=", inputPath);
  console.log("OUTPUT=", outputPath);
  console.log("TOTAL_ROWS=", records.length);
  console.log("CHANGED_PRIMARY=", changedPrimary);
  console.log("CHANGED_SUB=", changedSub);
  console.log("RESTORED_BY_SCORES=", restoredByScores);
  console.log("RESTORED_BY_REFERENCE=", restoredByReference);
}

try {
  main();
} catch (error) {
  console.error("REPAIR_ERROR:", error && error.message ? error.message : error);
  process.exit(1);
}
