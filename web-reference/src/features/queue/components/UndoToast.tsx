import { Undo2 } from 'lucide-react'
import { motion, AnimatePresence } from 'motion/react'

type UndoToastProps = {
  message: string | null
  onUndo: () => void
}

export function UndoToast({ message, onUndo }: UndoToastProps) {
  return (
    <AnimatePresence>
      {message && (
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 16 }}
          className="fixed bottom-6 left-1/2 z-50 flex -translate-x-1/2 items-center gap-3 rounded-lg border border-border-default bg-surface-raised px-4 py-3 text-sm text-text-primary shadow-elevation-3"
          role="status"
          aria-live="polite"
        >
          <span>{message}</span>
          <button
            type="button"
            onClick={onUndo}
            className="inline-flex min-h-[48px] items-center gap-1 rounded-md bg-surface-muted px-3 font-medium text-text-primary hover:bg-surface-hover focus:outline-none focus-visible:ring-2 focus-visible:ring-border-focus"
          >
            <Undo2 className="h-4 w-4" aria-hidden="true" />
            Undo
          </button>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
