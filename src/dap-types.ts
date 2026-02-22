/** DAP (Debug Adapter Protocol) message type definitions. */

export interface DAPMessage {
  seq: number;
  type: "request" | "response" | "event";
}

export interface DAPRequest extends DAPMessage {
  type: "request";
  command: string;
  arguments?: Record<string, unknown>;
}

export interface DAPResponse extends DAPMessage {
  type: "response";
  request_seq: number;
  success: boolean;
  command: string;
  message?: string;
  body?: Record<string, unknown>;
}

export interface DAPEvent extends DAPMessage {
  type: "event";
  event: string;
  body?: Record<string, unknown>;
}

export interface StackFrame {
  id: number;
  name: string;
  line: number;
  column: number;
  source?: {
    name?: string;
    path?: string;
    sourceReference?: number;
  };
}

export interface Variable {
  name: string;
  value: string;
  type?: string;
  variablesReference: number;
}

export interface Scope {
  name: string;
  variablesReference: number;
  expensive: boolean;
}

export interface Breakpoint {
  id?: number;
  verified: boolean;
  line?: number;
  message?: string;
}
