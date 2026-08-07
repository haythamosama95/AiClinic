import { useCallback, useEffect, useMemo, useState } from "react";
import type { CategoryId } from "@/catalog";
import { entitiesForCategory, entityById } from "@/catalog";
import type { OpsRunResult } from "@/lib/api";
import {
  loadConnection,
  saveConnection,
  type ConnectionConfig,
} from "@/lib/connection";
import { CategoryTabs } from "@/components/CategoryTabs";
import { ConnectionStrip } from "@/components/ConnectionStrip";
import { EntityForm } from "@/components/EntityForm";
import { EntityNav } from "@/components/EntityNav";
import { ResponsePanel } from "@/components/ResponsePanel";
import { SetupGuide } from "@/components/SetupGuide";

export function App() {
  const [connection, setConnection] = useState<ConnectionConfig>(() =>
    loadConnection(),
  );
  const [category, setCategory] = useState<CategoryId>("setup");
  const [entityId, setEntityId] = useState<string>("");
  const [response, setResponse] = useState<
    OpsRunResult | { error: string } | null
  >(null);

  const entities = useMemo(
    () => entitiesForCategory(category),
    [category],
  );

  const selectedEntity =
    (entityId ? entityById(entityId) : undefined) ?? entities[0];

  useEffect(() => {
    saveConnection(connection);
  }, [connection]);

  useEffect(() => {
    if (category === "setup") {
      setEntityId("");
      setResponse(null);
      return;
    }
    setEntityId((prev) => {
      if (prev && entities.some((e) => e.id === prev)) {
        return prev;
      }
      return entities[0]?.id ?? "";
    });
    setResponse(null);
  }, [category, entities]);

  const handleCategoryChange = useCallback((next: CategoryId) => {
    setCategory(next);
    setResponse(null);
  }, []);

  const handleEntitySelect = useCallback((id: string) => {
    setEntityId(id);
    setResponse(null);
  }, []);

  return (
    <div style={{ display: "flex", flexDirection: "column", minHeight: "100vh" }}>
      <header
        style={{
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          gap: "12px 24px",
          padding: "12px 16px",
          borderBottom: "1px solid var(--rule)",
          background: "var(--chalk)",
        }}
      >
        <div style={{ flexShrink: 0 }}>
          <div
            style={{
              fontWeight: 600,
              fontSize: 15,
              color: "var(--ink)",
              lineHeight: 1.2,
            }}
          >
            Platform Ops
          </div>
          <div style={{ fontSize: 12, color: "var(--steel)", marginTop: 2 }}>
            AiClinic AI gateway
          </div>
        </div>
        <ConnectionStrip connection={connection} onChange={setConnection} />
      </header>

      <CategoryTabs active={category} onChange={handleCategoryChange} />

      {category === "setup" ? (
        <div className="ops-setup-shell">
          <SetupGuide connection={connection} onResult={setResponse} />
          <ResponsePanel result={response} />
        </div>
      ) : (
        <div className="ops-workspace">
          {entities.length > 0 && selectedEntity ? (
            <EntityNav
              entities={entities}
              activeId={selectedEntity.id}
              onSelect={handleEntitySelect}
            />
          ) : null}

          <main
            style={{
              flex: 1,
              minWidth: 0,
              display: "flex",
              flexDirection: "column",
            }}
          >
            {selectedEntity ? (
              <div
                className="ops-fade-in"
                style={{ flex: 1, padding: "20px 24px", overflow: "auto" }}
              >
                <EntityForm
                  key={selectedEntity.id}
                  entity={selectedEntity}
                  connection={connection}
                  onResult={setResponse}
                />
              </div>
            ) : (
              <p style={{ padding: 24, fontSize: 13, color: "var(--steel)" }}>
                No entities in this category.
              </p>
            )}
            <ResponsePanel result={response} />
          </main>
        </div>
      )}
    </div>
  );
}
