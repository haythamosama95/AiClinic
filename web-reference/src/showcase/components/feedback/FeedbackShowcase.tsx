import { useState } from 'react'
import { Alert } from '@/components/alert'
import { Button } from '@/components/actions/Button'
import { ConfirmationDialog, Dialog } from '@/components/dialog'
import { Drawer } from '@/components/drawer'
import { EmptyState } from '@/components/empty-state'
import { ErrorState } from '@/components/error-state'
import { LoadingOverlay } from '@/components/loading-overlay'
import { Popover } from '@/components/ui/popover/Popover'
import { useToast } from '@/components/toast/Toast'
import { Card } from '@/components/card'
import {
  ShowcaseDemo,
  ShowcaseDemoGrid,
  ShowcaseSection,
} from '../../ShowcasePrimitives'

export function ToastShowcase() {
  const { toast } = useToast()

  return (
    <ShowcaseSection id="toast" title="Toast" componentName="useToast / ToastProvider">
      <ShowcaseDemoGrid columns={2}>
        {(['success', 'danger', 'info', 'neutral'] as const).map((variant) => (
          <ShowcaseDemo key={variant} label={variant}>
            <Button
              variant="secondary"
              size="sm"
              onClick={() =>
                toast({
                  variant,
                  message:
                    variant === 'success'
                      ? 'Published'
                      : variant === 'danger'
                        ? 'Could not save changes'
                        : variant === 'info'
                          ? 'Sync in progress'
                          : 'Draft saved',
                  action:
                    variant === 'success'
                      ? { label: 'Undo', onClick: () => undefined }
                      : undefined,
                })
              }
            >
              Show {variant}
            </Button>
          </ShowcaseDemo>
        ))}
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function AlertShowcase() {
  return (
    <ShowcaseSection id="alert" title="Inline alert" componentName="Alert">
      <div className="space-y-4">
        {(['info', 'success', 'warning', 'danger', 'ai'] as const).map((variant) => (
          <Alert
            key={variant}
            variant={variant}
            title={
              variant === 'ai'
                ? 'AI suggestions require your approval'
                : `${variant.charAt(0).toUpperCase()}${variant.slice(1)} notice`
            }
            dismissible
          >
            Contextual message for the {variant} variant.
          </Alert>
        ))}
      </div>
    </ShowcaseSection>
  )
}

export function DialogShowcase() {
  const [openSm, setOpenSm] = useState(false)
  const [openMd, setOpenMd] = useState(false)
  const [openLg, setOpenLg] = useState(false)
  const [openFull, setOpenFull] = useState(false)
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [financialOpen, setFinancialOpen] = useState(false)

  return (
    <ShowcaseSection id="dialog" title="Dialog" componentName="Dialog / ConfirmationDialog">
      <ShowcaseDemoGrid columns={2}>
        <ShowcaseDemo label="Sizes">
          <Button size="sm" onClick={() => setOpenSm(true)}>Small</Button>
          <Button size="sm" onClick={() => setOpenMd(true)}>Medium</Button>
          <Button size="sm" onClick={() => setOpenLg(true)}>Large</Button>
          <Button size="sm" onClick={() => setOpenFull(true)}>Full</Button>
        </ShowcaseDemo>
        <ShowcaseDemo label="Confirmation">
          <Button variant="danger" size="sm" onClick={() => setConfirmOpen(true)}>
            Destructive
          </Button>
          <Button size="sm" onClick={() => setFinancialOpen(true)}>
            Financial
          </Button>
        </ShowcaseDemo>
      </ShowcaseDemoGrid>

      <Dialog open={openSm} onOpenChange={setOpenSm} title="Small dialog" size="sm" footer={<Button onClick={() => setOpenSm(false)}>Close</Button>}>
        <p className="text-body text-text-secondary">Focused decision or short form.</p>
      </Dialog>
      <Dialog open={openMd} onOpenChange={setOpenMd} title="Medium dialog" size="md" footer={<Button onClick={() => setOpenMd(false)}>Save</Button>}>
        <p className="text-body text-text-secondary">Default size for create/edit forms.</p>
      </Dialog>
      <Dialog open={openLg} onOpenChange={setOpenLg} title="Large dialog" size="lg" footer={<Button onClick={() => setOpenLg(false)}>Done</Button>}>
        <p className="text-body text-text-secondary">More room for complex forms.</p>
      </Dialog>
      <Dialog open={openFull} onOpenChange={setOpenFull} title="Full dialog" size="full" footer={<Button onClick={() => setOpenFull(false)}>Close</Button>}>
        <p className="text-body text-text-secondary">Rare full-screen modal.</p>
      </Dialog>

      <ConfirmationDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        title="Archive patient?"
        description="This removes the patient from active lists. Visit history is retained."
        confirmLabel="Archive"
        variant="destructive"
        requireTypedConfirmation="ARCHIVE"
        onConfirm={() => undefined}
      />
      <ConfirmationDialog
        open={financialOpen}
        onOpenChange={setFinancialOpen}
        title="Void invoice INV-2026-0842?"
        description="This voids EGP 1,850.00 and cannot be undone."
        confirmLabel="Void invoice"
        variant="financial"
        onConfirm={() => undefined}
      />
    </ShowcaseSection>
  )
}

export function DrawerShowcase() {
  const [open, setOpen] = useState(false)

  return (
    <ShowcaseSection id="drawer" title="Drawer / Sheet" componentName="Drawer">
      <Button onClick={() => setOpen(true)}>Open drawer</Button>
      <Drawer
        open={open}
        onOpenChange={setOpen}
        title="Patient detail"
        description="Side panel without leaving context"
        footer={<Button onClick={() => setOpen(false)}>Close</Button>}
      >
        <p className="text-body text-text-secondary">Detail content for patient Layla Hassan.</p>
      </Drawer>
    </ShowcaseSection>
  )
}

export function PopoverShowcase() {
  return (
    <ShowcaseSection id="popover" title="Popover" componentName="Popover">
      <Popover
        trigger={<Button variant="secondary" size="sm">Open popover</Button>}
      >
        <div className="p-4 text-body-sm text-text-secondary">Quick edit or filter content.</div>
      </Popover>
    </ShowcaseSection>
  )
}

export function LoadingOverlayShowcase() {
  const [scoped, setScoped] = useState(true)

  return (
    <ShowcaseSection id="loading-overlay" title="Loading overlay" componentName="LoadingOverlay">
      <ShowcaseDemo label="Scoped">
        <LoadingOverlay loading={scoped} scoped label="Loading patients…">
          <Card className="h-32 w-full p-4">
            <p className="text-body text-text-secondary">Content beneath overlay</p>
          </Card>
        </LoadingOverlay>
        <Button size="sm" variant="ghost" onClick={() => setScoped((s) => !s)}>
          Toggle loading
        </Button>
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}

export function EmptyStateShowcase() {
  return (
    <ShowcaseSection id="empty-state" title="Empty states" componentName="EmptyState">
      <ShowcaseDemoGrid columns={2}>
        {(['first-run', 'no-results', 'no-access', 'error'] as const).map((variant) => (
          <EmptyState
            key={variant}
            variant={variant}
            action={variant === 'first-run' ? { label: 'Add patient', onClick: () => undefined } : undefined}
            shortcutHint={variant === 'first-run' ? ['⌘', 'N'] : undefined}
          />
        ))}
      </ShowcaseDemoGrid>
    </ShowcaseSection>
  )
}

export function ErrorStateShowcase() {
  return (
    <ShowcaseSection id="error-state" title="Error state" componentName="ErrorState">
      <ErrorState
        message="We could not load appointments. Check your connection and try again."
        onRetry={() => undefined}
      />
    </ShowcaseSection>
  )
}
