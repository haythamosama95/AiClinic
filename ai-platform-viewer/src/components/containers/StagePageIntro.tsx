import { useState, type ReactNode } from 'react'

interface StagePageIntroProps {
  eyebrow: string
  eyebrowClass?: string
  title: string
  lede?: ReactNode
  details?: ReactNode
  action?: ReactNode
}

export function StagePageIntro({
  eyebrow,
  eyebrowClass,
  title,
  lede,
  details,
  action,
}: StagePageIntroProps) {
  const [detailsOpen, setDetailsOpen] = useState(false)
  const collapsible = Boolean(details)

  return (
    <header className="stage-page__intro">
      <div className="stage-page__intro-row">
        <div className="stage-page__intro-title">
          {collapsible ? (
            <button
              type="button"
              className="stage-page__details-toggle"
              aria-expanded={detailsOpen}
              onClick={() => setDetailsOpen((open) => !open)}
            >
              <span className="stage-page__details-chevron" aria-hidden="true" />
              <span>
                <p
                  className={`stage-page__eyebrow${eyebrowClass ? ` ${eyebrowClass}` : ''}`}
                >
                  {eyebrow}
                </p>
                <h2>{title}</h2>
              </span>
            </button>
          ) : (
            <>
              <p
                className={`stage-page__eyebrow${eyebrowClass ? ` ${eyebrowClass}` : ''}`}
              >
                {eyebrow}
              </p>
              <h2>{title}</h2>
            </>
          )}
        </div>
        {action}
      </div>
      {collapsible ? (
        detailsOpen ? (
          <div className="stage-page__details">
            {lede ? <p className="stage-page__lede">{lede}</p> : null}
            {details}
          </div>
        ) : null
      ) : lede ? (
        <p className="stage-page__lede">{lede}</p>
      ) : null}
    </header>
  )
}
