import type { AppointmentStatus, ShiftStatus } from "@/lib/types";

const appointmentStyles: Record<
  AppointmentStatus,
  { dot: string; pill: string }
> = {
  scheduled: {
    dot: "bg-slate-400",
    pill: "bg-slate-100 text-slate-700 ring-slate-200",
  },
  confirmed: {
    dot: "bg-sky-500",
    pill: "bg-sky-50 text-sky-800 ring-sky-200",
  },
  checked_in: {
    dot: "bg-amber-500",
    pill: "bg-amber-50 text-amber-900 ring-amber-200",
  },
  in_progress: {
    dot: "bg-brand animate-pulse-soft",
    pill: "bg-brand-soft text-brand-ink ring-brand/20",
  },
  completed: {
    dot: "bg-emerald-500",
    pill: "bg-emerald-50 text-emerald-800 ring-emerald-200",
  },
  no_show: {
    dot: "bg-rose-400",
    pill: "bg-rose-50 text-rose-800 ring-rose-200",
  },
  cancelled: {
    dot: "bg-slate-300",
    pill: "bg-slate-50 text-slate-500 ring-slate-200",
  },
};

const shiftStyles: Record<ShiftStatus, string> = {
  on_shift: "bg-emerald-50 text-emerald-800 ring-emerald-200",
  break: "bg-amber-50 text-amber-900 ring-amber-200",
  ending_soon: "bg-orange-50 text-orange-800 ring-orange-200",
};

interface StatusBadgeProps {
  label: string;
  variant?: "appointment" | "shift" | "neutral";
  status?: AppointmentStatus | ShiftStatus;
}

export function StatusBadge({
  label,
  variant = "neutral",
  status,
}: StatusBadgeProps) {
  let className = "bg-slate-100 text-slate-700 ring-slate-200";

  if (variant === "appointment" && status) {
    className = appointmentStyles[status as AppointmentStatus].pill;
  } else if (variant === "shift" && status) {
    className = shiftStyles[status as ShiftStatus];
  }

  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset ${className}`}
    >
      {label}
    </span>
  );
}

export function StatusDot({
  status,
}: {
  status: AppointmentStatus;
}) {
  return (
    <span
      className={`inline-block h-2 w-2 shrink-0 rounded-full ${appointmentStyles[status].dot}`}
      aria-hidden
    />
  );
}
