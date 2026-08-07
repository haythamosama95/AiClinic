import { CATEGORIES } from "@/catalog";
import type { CategoryId } from "@/catalog";

type CategoryTabsProps = {
  active: CategoryId;
  onChange: (category: CategoryId) => void;
};

export function CategoryTabs({ active, onChange }: CategoryTabsProps) {
  return (
    <div
      role="tablist"
      aria-label="Categories"
      style={{
        display: "flex",
        borderBottom: "1px solid var(--rule)",
      }}
    >
      {CATEGORIES.map((cat) => {
        const isActive = cat.id === active;
        return (
          <button
            key={cat.id}
            type="button"
            role="tab"
            aria-selected={isActive}
            onClick={() => onChange(cat.id)}
            style={{
              padding: "10px 20px",
              border: "1px solid var(--rule)",
              borderBottom: isActive
                ? "1px solid var(--teal)"
                : "1px solid var(--rule)",
              marginBottom: isActive ? -1 : 0,
              background: isActive ? "var(--teal)" : "var(--chalk)",
              color: isActive ? "#fff" : "var(--ink)",
              cursor: "pointer",
              fontWeight: 500,
              fontSize: 14,
              transition:
                "background 180ms ease, color 180ms ease, border-color 180ms ease",
            }}
          >
            {cat.label}
          </button>
        );
      })}
    </div>
  );
}
