import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { AppProviders } from '@/providers/AppProviders'
import { ShowcaseApp } from '@/pages/ShowcaseApp'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AppProviders>
      <ShowcaseApp />
    </AppProviders>
  </StrictMode>,
)
