import type { OpsRunResult } from "@/lib/api";
import { prettyBody } from "@/lib/format";

type ResponsePanelProps = {
  result: OpsRunResult | { error: string } | null;
};

export function ResponsePanel({ result }: ResponsePanelProps) {
  if (!result) {
    return (
      <div
        style={{
          padding: 16,
          borderTop: "1px solid var(--rule)",
          background: "var(--chalk)",
          color: "var(--steel)",
          fontSize: 13,
        }}
      >
        No response yet.
      </div>
    );
  }

  if ("error" in result) {
    return (
      <div
        style={{
          padding: 16,
          borderTop: "1px solid var(--rule)",
          background: "var(--chalk)",
        }}
      >
        <p style={{ margin: "0 0 8px", fontSize: 13, color: "var(--warn)" }}>
          Error
        </p>
        <pre
          className="ops-mono"
          style={{
            margin: 0,
            fontSize: 12,
            whiteSpace: "pre-wrap",
            wordBreak: "break-word",
            color: "var(--ink)",
          }}
        >
          {result.error}
        </pre>
      </div>
    );
  }

  const displayBody = prettyBody(result.bodyText);

  return (
    <div
      style={{
        padding: 16,
        borderTop: "1px solid var(--rule)",
        background: "var(--chalk)",
      }}
    >
      <div
        className="ops-mono"
        style={{
          display: "flex",
          flexWrap: "wrap",
          gap: "8px 20px",
          fontSize: 12,
          color: "var(--steel)",
          marginBottom: 12,
        }}
      >
        <span>
          status{" "}
          <strong style={{ color: "var(--ink)" }}>{result.status}</strong>
        </span>
        <span>
          duration{" "}
          <strong style={{ color: "var(--ink)" }}>{result.durationMs}ms</strong>
        </span>
        <span>
          content-type{" "}
          <strong style={{ color: "var(--ink)" }}>
            {result.contentType || "—"}
          </strong>
        </span>
      </div>
      <pre
        className="ops-mono"
        style={{
          margin: 0,
          fontSize: 12,
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
          color: "var(--ink)",
          maxHeight: 480,
          overflow: "auto",
        }}
      >
        {displayBody}
      </pre>
    </div>
  );
}
