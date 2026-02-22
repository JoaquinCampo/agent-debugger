/** Language detection + adapter lookup. */

import { extname } from "node:path";
import type { AdapterConfig } from "./base.js";
import { PythonAdapter } from "./python.js";
import { NodeAdapter } from "./node.js";
import { GoAdapter } from "./go.js";
import { RustAdapter } from "./rust.js";

const EXTENSION_MAP: Record<string, string> = {
  ".py": "python",
  ".js": "node",
  ".mjs": "node",
  ".cjs": "node",
  ".ts": "node",
  ".mts": "node",
  ".tsx": "node",
  ".go": "go",
  ".rs": "rust",
  ".c": "rust",
  ".cpp": "rust",
  ".cc": "rust",
};

const adapters: Record<string, () => AdapterConfig> = {
  python: () => new PythonAdapter(),
  node: () => new NodeAdapter(),
  go: () => new GoAdapter(),
  rust: () => new RustAdapter(),
};

/** Detect language from file extension. */
export function detectLanguage(filePath: string): string | null {
  const ext = extname(filePath).toLowerCase();
  return EXTENSION_MAP[ext] ?? null;
}

/** Get an adapter by language name. */
export function getAdapter(language: string): AdapterConfig | null {
  const factory = adapters[language];
  return factory ? factory() : null;
}

/** Detect language from file and return adapter. */
export function getAdapterForFile(filePath: string): AdapterConfig | null {
  const lang = detectLanguage(filePath);
  if (!lang) return null;
  return getAdapter(lang);
}

export { type AdapterConfig } from "./base.js";
