import { useEffect, useState } from 'react'
import { COMMERCIAL_INVOICE_OPERATIONS } from '@/catalog/commercial-invoices'
import type { JourneyOperationDefinition, JourneyStageMeta } from '@/catalog/journey-types'
import {
  CommandCard,
  CommandDeck,
  CommandDeckSection,
  CommandPanel,
  CommandPanelField,
  CommandPanelFields,
  journeyAuthLabel,
  journeyAuthLine,
  journeyCommandTone,
  StagePage,
  StagePageIntro,
} from '@/components/containers'
import {
  journeyCommandFieldCount,
  journeyCommandPath,
} from '@/components/JourneyCommandPanel'
import { RequestInspector } from '@/components/RequestInspector'
import {
  buildJourneyDefaultParams,
  validateJourneyParams,
} from '@/lib/journey-api'
import { fetchInvoiceDetail, fetchIssuedInvoices } from '@/lib/dev-api'
import type { HttpExchange } from '@/types'

const INVOICES_META: JourneyStageMeta = {
  id: 'invoices',
  navLabel: 'Invoices',
  navNote: 'G4 invoice inspect',
  eyebrow: 'Commercial · Issued invoices',
  title: 'G4 invoice list and rollup evidence',
  lede:
    'List and inspect issued G4 invoice rows from local D1 via wrangler d1 execute --local. SQL and JSON appear in the raw inspector — no Worker invoice GET and no payment-provider call.',
  accentClass: 'stage-accent--settlement',
  cardClass: 'operation-card--settlement',
  buttonClass: 'settlement-button',
}

function InvoiceInspectPanel({
  operation,
  onClose,
}: {
  operation: JourneyOperationDefinition
  onClose: () => void
}) {
  const [params, setParams] = useState<Record<string, string>>(() =>
    buildJourneyDefaultParams(operation.fields),
  )
  const [exchange, setExchange] = useState<HttpExchange | null>(null)
  const [inspectorOpen, setInspectorOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [sendError, setSendError] = useState<string | null>(null)

  useEffect(() => {
    setParams(buildJourneyDefaultParams(operation.fields))
    setExchange(null)
    setInspectorOpen(false)
    setSendError(null)
  }, [operation.id, operation.fields])

  async function handleSend() {
    setSendError(null)
    setBusy(true)
    try {
      const validationError = validateJourneyParams(operation.fields, params)
      if (validationError) {
        throw new Error(validationError)
      }

      const result =
        operation.id === 'invoice-list'
          ? await fetchIssuedInvoices()
          : await fetchInvoiceDetail(
              params.installation_id?.trim() ?? '',
              params.period?.trim() ?? '',
            )

      setExchange(result)
      setInspectorOpen(true)
    } catch (error) {
      setSendError(error instanceof Error ? error.message : 'Inspect failed')
      setInspectorOpen(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <CommandPanel
      tone={journeyCommandTone(operation)}
      title={operation.title}
      method={operation.method}
      path={operation.path}
      summary={operation.summary}
      successNote={operation.successNote}
      failures={operation.failures}
      responseId={`invoice-responses-${operation.id}`}
      onClose={onClose}
      authLine={journeyAuthLine(operation.auth, true)}
      manifest={
        operation.fields.length > 0 ? (
          <CommandPanelFields>
            {operation.fields.map((field) => (
              <CommandPanelField
                key={field.name}
                name={field.name}
                scope={field.scope}
                hint={field.hint}
                wide={field.wide}
                value={params[field.name] ?? ''}
                placeholder={field.defaultValue || field.hint || ''}
                onChange={(value) =>
                  setParams((current) => ({ ...current, [field.name]: value }))
                }
              />
            ))}
          </CommandPanelFields>
        ) : undefined
      }
      actions={
        <button
          type="button"
          className={INVOICES_META.buttonClass}
          onClick={() => void handleSend()}
          disabled={busy}
        >
          {busy ? 'Inspecting…' : 'Run inspect'}
        </button>
      }
      inspector={
        inspectorOpen ? (
          sendError ? (
            <p className="operation-card__error" role="alert">
              {sendError}
            </p>
          ) : exchange ? (
            <RequestInspector exchange={exchange} />
          ) : null
        ) : null
      }
    />
  )
}

export function InvoicesPage() {
  const [selectedCommand, setSelectedCommand] = useState<string | null>(null)
  const selectedOperation =
    COMMERCIAL_INVOICE_OPERATIONS.find((operation) => operation.id === selectedCommand) ??
    null

  return (
    <StagePage accentClass={INVOICES_META.accentClass}>
      <StagePageIntro
        eyebrow={INVOICES_META.eyebrow}
        eyebrowClass={INVOICES_META.accentClass}
        title={INVOICES_META.title}
        lede={INVOICES_META.lede}
      />

      <CommandDeck
        eyebrow="Commands"
        lede="Local D1 inspect — SQL appears as request raw, JSON rows as response raw."
        ariaLabel={`${INVOICES_META.title} commands`}
        panel={
          selectedOperation ? (
            <InvoiceInspectPanel
              key={selectedOperation.id}
              operation={selectedOperation}
              onClose={() => setSelectedCommand(null)}
            />
          ) : null
        }
      >
        <CommandDeckSection title="Issued invoices" />
        {COMMERCIAL_INVOICE_OPERATIONS.map((operation) => (
          <CommandCard
            key={operation.id}
            method={operation.method}
            title={operation.title}
            path={journeyCommandPath(operation)}
            authLabel={journeyAuthLabel(operation.auth)}
            fieldCount={journeyCommandFieldCount(operation)}
            tone={journeyCommandTone(operation)}
            selected={selectedCommand === operation.id}
            onSelect={() =>
              setSelectedCommand((current) =>
                current === operation.id ? null : operation.id,
              )
            }
          />
        ))}
      </CommandDeck>
    </StagePage>
  )
}
