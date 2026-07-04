import Link from "next/link";

interface ThemeChromeProps {
  themeName: string;
  className?: string;
  backHref?: string;
  backLabel?: string;
}

export function ThemeChrome({
  themeName,
  className = "",
  backHref = "/",
  backLabel = "All themes",
}: ThemeChromeProps) {
  return (
    <nav
      className={`flex items-center justify-between gap-4 text-sm ${className}`}
      aria-label="Theme navigation"
    >
      <Link
        href={backHref}
        className="inline-flex items-center gap-1.5 opacity-70 transition-opacity hover:opacity-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
      >
        <span aria-hidden>←</span>
        {backLabel}
      </Link>
      <span className="text-xs font-medium uppercase tracking-wider opacity-50">
        {themeName}
      </span>
    </nav>
  );
}
