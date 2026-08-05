/** Clears scroll locks left behind by dialogs, drawers, or nested popovers. */
export function releaseOverlayLocks() {
  document.body.style.overflow = ''
  document.body.style.pointerEvents = ''
  document.body.removeAttribute('data-scroll-locked')
}
