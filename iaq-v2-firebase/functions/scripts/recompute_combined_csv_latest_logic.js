const fs = require("fs");
const path = require("path");

const IAQI_K_REGRESSION_WINDOW_MS = 300 * 1000;
const IAQI_K_REGRESSION_HISTORY_LIMIT = 400;
const IAQI_K_REGRESSION_MIN_SAMPLES = 15;
const IAQI_K_PM_NOISE_THRESHOLD = 0.99;
const IAQI_K_CO2_BASELINE = 420;

function parseArgs(argv) {
  const args = {
    inputPath: null,
    outputPath: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if ((token === "--input" || token === "-i") && argv[i + 1]) {
      args.inputPath = argv[i + 1].trim();
      i += 1;
      continue;
    }

    if ((token === "--output" || token === "-o") && argv[i + 1]) {
      args.outputPath = argv[i + 1].trim();
      i += 1;
      continue;
    }
  }

  return args;
}

function toFiniteNumberOrNull(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === "string" && value.trim() === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return parsed;
}

function toMillisOrNull(value) {
  if (!value) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.getTime();
}

function roundTo(value, digits = 3) {
  const factor = Math.pow(10, digits);
  return Math.round(value * factor) / factor;
}

function csvEscape(value) {
  const text = value == null ? "" : String(value);
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
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

  if (!rows.length) return { headers: [], records: [] };

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

function runLogLinearRegression(samples, valueSelector, options = {}) {
  const minSamples = Number.isFinite(options.minSamples)
    ? options.minSamples
    : IAQI_K_REGRESSION_MIN_SAMPLES;
  const checkNoise = options.checkNoise === true;
  const noiseThreshold = Number.isFinite(options.noiseThreshold)
    ? options.noiseThreshold
    : IAQI_K_PM_NOISE_THRESHOLD;

  const normalized = samples
    .filter((sample) => Number.isFinite(sample?.t) && Number.isFinite(sample?.v))
    .sort((a, b) => a.t - b.t);

  if (normalized.length < minSamples) {
    return {
      valid: false,
      k: null,
      r2: null,
      sampleCount: normalized.length,
    };
  }

  if (checkNoise) {
    const maxVal = normalized.reduce((maxValue, sample) => Math.max(maxValue, sample.v), -Infinity);
    if (!Number.isFinite(maxVal) || maxVal < noiseThreshold) {
      return {
        valid: false,
        k: null,
        r2: null,
        sampleCount: normalized.length,
      };
    }
  }

  const firstTs = normalized[0].t;
  const points = [];

  for (const sample of normalized) {
    const x = (sample.t - firstTs) / 3600000;
    const y = Number(valueSelector(sample));
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      continue;
    }
    points.push({ x, y });
  }

  const n = points.length;
  if (n < minSamples) {
    return {
      valid: false,
      k: null,
      r2: null,
      sampleCount: n,
    };
  }

  let sumX = 0;
  let sumY = 0;
  let sumXY = 0;
  let sumXX = 0;
  let sumYY = 0;

  for (const point of points) {
    sumX += point.x;
    sumY += point.y;
    sumXY += point.x * point.y;
    sumXX += point.x * point.x;
    sumYY += point.y * point.y;
  }

  const denom = (n * sumXX) - (sumX * sumX);
  if (!Number.isFinite(denom) || denom === 0) {
    return {
      valid: false,
      k: null,
      r2: null,
      sampleCount: n,
    };
  }

  const slope = ((n * sumXY) - (sumX * sumY)) / denom;
  const intercept = (sumY - slope * sumX) / n;
  const ssTot = sumYY - ((sumY * sumY) / n);
  let ssRes = 0;

  for (const point of points) {
    const fitted = (slope * point.x) + intercept;
    ssRes += (point.y - fitted) * (point.y - fitted);
  }

  const r2 = ssTot === 0 ? 1 : Math.max(0, 1 - (ssRes / ssTot));
  const k = roundTo(-slope, 3);

  return {
    valid: Number.isFinite(k),
    k: Number.isFinite(k) ? k : null,
    r2: Number.isFinite(r2) ? roundTo(r2, 4) : null,
    sampleCount: n,
  };
}

function calculateIaqi({
  co2,
  pm25,
  k,
  voc,
  temp,
  humi,
}) {
  const safeCo2 = Number.isFinite(Number(co2)) ? Number(co2) : 600;
  const safePm25 = Number.isFinite(Number(pm25)) ? Number(pm25) : 15;
  const safeK = Number.isFinite(Number(k)) ? Number(k) : 0;
  const safeVoc = Number.isFinite(Number(voc)) ? Number(voc) : 100;
  const safeTemp = Number.isFinite(Number(temp)) ? Number(temp) : 24;
  const safeHumi = Number.isFinite(Number(humi)) ? Number(humi) : 50;

  const rCo2 = Math.max(0, (safeCo2 - 600) / 400);
  const rPm25 = Math.max(0, (safePm25 - 15) / 35);
  const rK = Math.max(0, (6 - safeK) / 2);
  const rVoc = Math.max(0, (safeVoc - 100) / 100);
  const rTemp = Math.max(0, Math.abs(safeTemp - 24) / 4);
  const rHumi = Math.max(0, Math.abs(safeHumi - 50) / 10);
  const rTh = Math.max(rTemp, rHumi);

  const mScoreRaw = Math.max(rCo2, Math.max(rPm25, Math.max(rK, rVoc)));

  let primaryGrade = "좋음";
  let subLevel = null;
  let eScoreRaw = null;
  let iScoreRaw = null;

  if (mScoreRaw > 0 && mScoreRaw < 1) {
    primaryGrade = "보통";
    iScoreRaw =
      (0.2 * rCo2) +
      (0.2 * rPm25) +
      (0.2 * rK) +
      (0.2 * rVoc) +
      (0.2 * rTh);
  } else if (mScoreRaw >= 1) {
    primaryGrade = "나쁨";
    eScoreRaw =
      Math.max(0, rCo2 - 1) +
      Math.max(0, rPm25 - 1) +
      Math.max(0, rK - 1) +
      Math.max(0, rVoc - 1);

    if (eScoreRaw < 1) {
      subLevel = "경미한 악화 (나쁨-1)";
    } else if (eScoreRaw < 2) {
      subLevel = "중간수준 악화 (나쁨-2)";
    } else if (eScoreRaw < 3) {
      subLevel = "심각한 악화 (나쁨-3)";
    } else {
      subLevel = "매우 위험 (나쁨-4)";
    }
  }

  return {
    primary_grade: primaryGrade,
    sub_level: subLevel,
    m_score: roundTo(mScoreRaw, 3),
    e_score: eScoreRaw == null ? null : roundTo(eScoreRaw, 3),
    i_score: iScoreRaw == null ? null : roundTo(iScoreRaw, 3),
  };
}

function buildIaqiBundle({
  co2,
  pm25,
  k,
  voc,
  temp,
  humi,
}) {
  const pm25Number = Number(pm25);
  if (!Number.isFinite(pm25Number) || pm25Number < 0) {
    return null;
  }

  const kNumber = Number(k);
  if (!Number.isFinite(kNumber) || kNumber < 0) {
    return null;
  }

  const iaqi = calculateIaqi({
    co2,
    pm25: pm25Number,
    k: kNumber,
    voc,
    temp,
    humi,
  });

  const mScore = Number(iaqi.m_score);
  const iaqiScore = Number.isFinite(mScore) ? roundTo(mScore, 3) : null;

  return {
    iaqi,
    iaqiScore,
    pm25: pm25Number,
  };
}

function toCsvText(rows, columns) {
  const lines = [columns.join(",")];
  for (const row of rows) {
    const line = columns.map((col) => csvEscape(row[col]));
    lines.push(line.join(","));
  }
  return lines.join("\n");
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.inputPath) {
    throw new Error("Missing --input <csvPath>");
  }

  const inputPath = path.resolve(args.inputPath);
  if (!fs.existsSync(inputPath)) {
    throw new Error(`Input CSV not found: ${inputPath}`);
  }

  const outputPath = args.outputPath
    ? path.resolve(args.outputPath)
    : path.join(
      path.dirname(inputPath),
      `${path.basename(inputPath, ".csv")}_recomputed_latest_logic.csv`
    );

  const rawText = fs.readFileSync(inputPath, "utf8");
  const { headers, records } = parseCsv(rawText);
  if (!records.length) {
    throw new Error("CSV has no data rows");
  }

  const requiredColumns = ["timestamp", "co2", "pm25", "temp", "humidity", "tvoc"];
  for (const col of requiredColumns) {
    if (!headers.includes(col)) {
      throw new Error(`Required column missing: ${col}`);
    }
  }

  const entries = records.map((row, index) => {
    const tsMs = toMillisOrNull(row.timestamp || row.createdAt);
    return {
      index,
      row,
      tsMs,
      sourceCollection: String(row.source_collection || "").trim().toLowerCase(),
    };
  });

  const validEntries = entries
    .filter((entry) => Number.isFinite(entry.tsMs))
    .sort((a, b) => a.tsMs - b.tsMs || a.index - b.index);

  const historyEntries = validEntries.filter((entry) => entry.sourceCollection === "history");

  let historyPtr = 0;
  const historyWindow = [];
  const kSourceDist = {};

  for (const entry of validEntries) {
    const measuredAtMs = entry.tsMs;
    const windowStartMs = measuredAtMs - IAQI_K_REGRESSION_WINDOW_MS;

    while (
      historyPtr < historyEntries.length &&
      historyEntries[historyPtr].tsMs <= measuredAtMs + 1000
    ) {
      historyWindow.push(historyEntries[historyPtr]);
      historyPtr += 1;
    }

    while (historyWindow.length && historyWindow[0].tsMs < windowStartMs) {
      historyWindow.shift();
    }

    const recentHistory = historyWindow.slice(-IAQI_K_REGRESSION_HISTORY_LIMIT);

    const pmSamples = [];
    const co2Samples = [];

    for (const hist of recentHistory) {
      const pmValue = toFiniteNumberOrNull(hist.row.pm25);
      if (Number.isFinite(pmValue) && pmValue >= 0) {
        pmSamples.push({ t: hist.tsMs, v: pmValue });
      }

      const co2Value = toFiniteNumberOrNull(hist.row.co2);
      if (Number.isFinite(co2Value) && co2Value >= 0) {
        co2Samples.push({
          t: hist.tsMs,
          v: Math.max(co2Value - IAQI_K_CO2_BASELINE, 10),
        });
      }
    }

    const pmNow = toFiniteNumberOrNull(entry.row.pm25);
    if (Number.isFinite(pmNow) && pmNow >= 0) {
      pmSamples.push({ t: measuredAtMs, v: pmNow });
    }

    const co2Now = toFiniteNumberOrNull(entry.row.co2);
    if (Number.isFinite(co2Now) && co2Now >= 0) {
      co2Samples.push({
        t: measuredAtMs,
        v: Math.max(co2Now - IAQI_K_CO2_BASELINE, 10),
      });
    }

    const pmRegression = runLogLinearRegression(
      pmSamples,
      (sample) => Math.log(Math.max(sample.v, 1e-6)),
      {
        minSamples: IAQI_K_REGRESSION_MIN_SAMPLES,
        checkNoise: true,
        noiseThreshold: IAQI_K_PM_NOISE_THRESHOLD,
      }
    );

    const co2Regression = runLogLinearRegression(
      co2Samples,
      (sample) => Math.log(Math.max(sample.v, 1e-6)),
      {
        minSamples: IAQI_K_REGRESSION_MIN_SAMPLES,
        checkNoise: false,
      }
    );

    let resolvedK = 0;
    let source = "computed_co2_insufficient_samples";

    if (co2Regression.valid && Number.isFinite(co2Regression.k)) {
      resolvedK = Math.max(co2Regression.k, 0);
      source = "computed_co2_regression";
    }

    const kEffective = roundTo(resolvedK, 3);

    const bundle = buildIaqiBundle({
      co2: toFiniteNumberOrNull(entry.row.co2),
      pm25: toFiniteNumberOrNull(entry.row.pm25),
      k: kEffective,
      voc: toFiniteNumberOrNull(entry.row.tvoc),
      temp: toFiniteNumberOrNull(entry.row.temp),
      humi: toFiniteNumberOrNull(entry.row.humidity),
    });

    entry.row.k = kEffective;
    entry.row.kEffective = kEffective;
    entry.row.kSource = source;
    entry.row.kCo2 = co2Regression.valid && Number.isFinite(co2Regression.k)
      ? roundTo(Math.max(co2Regression.k, 0), 3)
      : "";
    entry.row.kPm25 = pmRegression.valid && Number.isFinite(pmRegression.k)
      ? roundTo(Math.max(pmRegression.k, 0), 3)
      : "";
    entry.row.kR2Co2 = Number.isFinite(co2Regression.r2) ? co2Regression.r2 : "";
    entry.row.kR2Pm25 = Number.isFinite(pmRegression.r2) ? pmRegression.r2 : "";
    entry.row.kSampleCountCo2 = Number.isFinite(co2Regression.sampleCount)
      ? co2Regression.sampleCount
      : "";
    entry.row.kSampleCountPm25 = Number.isFinite(pmRegression.sampleCount)
      ? pmRegression.sampleCount
      : "";

    entry.row["iaqi.primary_grade"] = bundle?.iaqi?.primary_grade || "";
    entry.row["iaqi.sub_level"] = bundle?.iaqi?.sub_level || "";
    entry.row["iaqi.m_score"] = Number.isFinite(bundle?.iaqi?.m_score)
      ? bundle.iaqi.m_score
      : "";
    entry.row["iaqi.e_score"] = Number.isFinite(bundle?.iaqi?.e_score)
      ? bundle.iaqi.e_score
      : "";
    entry.row["iaqi.i_score"] = Number.isFinite(bundle?.iaqi?.i_score)
      ? bundle.iaqi.i_score
      : "";
    entry.row.iaqiScore = Number.isFinite(bundle?.iaqiScore) ? bundle.iaqiScore : "";

    kSourceDist[source] = (kSourceDist[source] || 0) + 1;
  }

  const newColumns = [
    "kEffective",
    "kSource",
    "kCo2",
    "kPm25",
    "kR2Co2",
    "kR2Pm25",
    "kSampleCountCo2",
    "kSampleCountPm25",
  ];

  const columns = [...headers];
  for (const col of newColumns) {
    if (!columns.includes(col)) {
      columns.push(col);
    }
  }

  const outputRows = records;
  const outputCsv = toCsvText(outputRows, columns);

  fs.writeFileSync(outputPath, outputCsv, "utf8");

  console.log("INPUT=", inputPath);
  console.log("OUTPUT=", outputPath);
  console.log("TOTAL_ROWS=", records.length);
  console.log("VALID_TIMESTAMP_ROWS=", validEntries.length);
  console.log("K_SOURCE_DIST=", JSON.stringify(kSourceDist));
}

try {
  main();
} catch (error) {
  console.error("RECOMPUTE_ERROR:", error && error.message ? error.message : error);
  process.exit(1);
}
