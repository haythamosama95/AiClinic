import type { EntityDef } from "@/catalog";

type EntityNavProps = {
  entities: EntityDef[];
  activeId: string;
  onSelect: (id: string) => void;
};

export function EntityNav({ entities, activeId, onSelect }: EntityNavProps) {
  return (
    <nav aria-label="Entities" className="ops-entity-nav">
      {entities.map((entity) => {
        const isActive = entity.id === activeId;
        return (
          <button
            key={entity.id}
            type="button"
            onClick={() => onSelect(entity.id)}
            style={{
              display: "block",
              width: "100%",
              textAlign: "left",
              padding: "10px 14px",
              border: "none",
              borderLeft: isActive
                ? "3px solid var(--teal-deep)"
                : "3px solid transparent",
              background: isActive ? "var(--chalk)" : "transparent",
              color: "var(--ink)",
              cursor: "pointer",
            }}
          >
            <span style={{ display: "block", fontSize: 14, fontWeight: 500 }}>
              {entity.title}
              {entity.dangerous && (
                <span
                  style={{
                    marginLeft: 6,
                    fontSize: 11,
                    fontWeight: 500,
                    color: "var(--warn)",
                  }}
                >
                  danger
                </span>
              )}
            </span>
            <span
              className="ops-mono"
              style={{
                display: "block",
                fontSize: 11,
                color: "var(--steel)",
                marginTop: 2,
              }}
            >
              {entity.id}
            </span>
          </button>
        );
      })}
    </nav>
  );
}
