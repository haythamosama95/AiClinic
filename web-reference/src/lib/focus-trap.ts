export function trapFocus(container: HTMLElement, event: KeyboardEvent) {
  if (event.key !== 'Tab') return

  const focusable = container.querySelectorAll<HTMLElement>(
    'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
  )
  const elements = Array.from(focusable).filter((el) => !el.hasAttribute('disabled'))
  if (elements.length === 0) return

  const first = elements[0]
  const last = elements[elements.length - 1]

  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault()
    first.focus()
  }
}
