import { ArrowLeft, ArrowRight, Star } from 'lucide-react'
import type { Transition, Variants } from 'motion/react'
import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { createPortal } from 'react-dom'
import { Button } from '@/components/actions/Button'
import { AiClinicMark } from '@/components/brand/AiClinicMark'
import { FormField } from '@/components/ui/form-field/FormField'
import { PasswordInput } from '@/components/ui/password-input/PasswordInput'
import { TextInput } from '@/components/ui/text-input/TextInput'
import { cn } from '@/lib/cn'
import { trapFocus } from '@/lib/focus-trap'
import { getReducedMotion, motionPresets, resolveTransition } from '@/lib/motion'

const testimonials = [
  {
    quote:
      'AiClinic keeps our front desk, clinicians, and billing aligned without slowing anyone down. It feels calm even on busy mornings.',
    name: 'Dr. Nadia Hassan',
    title: 'Medical Director',
    organization: 'Downtown Clinic',
    image: 'https://www.untitledui.com/images/portraits/person-03',
  },
  {
    quote:
      'Patient records, appointments, and invoices finally live in one place. The team adopted it in days, not weeks.',
    name: 'Omar Farouk',
    title: 'Practice Manager',
    organization: 'Nasr City',
    image: 'https://www.untitledui.com/marketing/girl.webp',
  },
  {
    quote:
      'The workflow is focused and predictable. We spend less time hunting for information and more time with patients.',
    name: 'Dr. Layla Mansour',
    title: 'Family Physician',
    organization: 'Alexandria',
    image: 'https://www.untitledui.com/marketing/podcast-girl.webp',
  },
] as const

const carouselVariants: Variants = {
  enter: (direction: number) => ({
    x: direction > 0 ? 500 : -500,
    opacity: 0,
  }),
  center: {
    x: 0,
    zIndex: 1,
    opacity: 1,
  },
  exit: (direction: number) => ({
    x: direction < 0 ? 500 : -500,
    zIndex: 0,
    opacity: 0,
  }),
}

const carouselTransition: Transition = {
  type: 'tween',
  duration: getReducedMotion() ? 0.01 : 0.8,
  ease: [0.8, 0, 0.2, 1],
}

function wrapIndex(min: number, max: number, value: number) {
  const rangeSize = max - min
  return ((((value - min) % rangeSize) + rangeSize) % rangeSize) + min
}

export type LoginPageProps = {
  onLogin?: () => void
  onForgotPassword?: () => void
}

export function LoginPage({ onLogin, onForgotPassword }: LoginPageProps) {
  const dialogRef = useRef<HTMLDivElement>(null)
  const titleId = useId()
  const descriptionId = useId()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [{ page, direction, count }, setCarousel] = useState({
    page: 0,
    direction: 0,
    count: 0,
  })

  const currentTestimonial = wrapIndex(0, testimonials.length, page)
  const showBlur = !getReducedMotion()

  useEffect(() => {
    document.body.style.overflow = 'hidden'
    window.setTimeout(() => {
      dialogRef.current?.querySelector<HTMLElement>('input')?.focus()
    }, 50)

    const onKeyDown = (event: KeyboardEvent) => {
      if (dialogRef.current) trapFocus(dialogRef.current, event)
    }
    document.addEventListener('keydown', onKeyDown)

    return () => {
      document.body.style.overflow = ''
      document.removeEventListener('keydown', onKeyDown)
    }
  }, [])

  const navigateCarousel = (nextDirection: number) => {
    setCarousel({
      page: page + nextDirection,
      direction: nextDirection,
      count: count + 1,
    })
  }

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setLoading(true)
    window.setTimeout(() => {
      setLoading(false)
      onLogin?.()
    }, 600)
  }

  return createPortal(
    <div className="fixed inset-0 z-[2000] flex items-center justify-center p-4 sm:p-6">
      <motion.div
        aria-hidden
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        transition={resolveTransition(motionPresets.fade)}
        className={cn(
          'absolute inset-0 bg-surface-backdrop/60',
          showBlur && 'backdrop-blur-[2px]',
        )}
      />

      <motion.div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={descriptionId}
        initial="hidden"
        animate="visible"
        exit="exit"
        variants={motionPresets.modal.variants}
        transition={resolveTransition(motionPresets.modal)}
        className="relative grid w-full max-w-[960px] overflow-hidden rounded-2xl border border-border-default bg-surface-default shadow-elevation-3 lg:grid-cols-2 lg:max-h-[min(90dvh,680px)]"
      >
        <div className="flex max-h-[min(90dvh,680px)] flex-col overflow-y-auto px-6 py-8 sm:px-8">
          <div className="flex w-full flex-col gap-8">
            <header>
              <AiClinicMark />
            </header>

            <div className="flex flex-col gap-2">
              <h1 id={titleId} className="text-h1 text-text-primary">
                Welcome back
              </h1>
              <p id={descriptionId} className="text-body text-text-secondary">
                Sign in with your clinic credentials to continue.
              </p>
            </div>

            <form className="flex flex-col gap-6" onSubmit={handleSubmit} noValidate>
              <div className="flex flex-col gap-5">
                <FormField id="login-username" label="Username" required>
                  <TextInput
                    id="login-username"
                    name="username"
                    size="lg"
                    autoComplete="username"
                    placeholder="Enter your username"
                    value={username}
                    onChange={(event) => setUsername(event.target.value)}
                    required
                  />
                </FormField>

                <FormField id="login-password" label="Password" required>
                  <PasswordInput
                    id="login-password"
                    name="password"
                    size="lg"
                    autoComplete="current-password"
                    placeholder="Enter your password"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    required
                  />
                </FormField>
              </div>

              <div className="flex justify-end">
                <Button
                  type="button"
                  variant="link"
                  size="md"
                  className="min-w-0"
                  onClick={() => onForgotPassword?.()}
                >
                  Forgot your password?
                </Button>
              </div>

              <Button type="submit" size="lg" loading={loading} className="w-full">
                Log in
              </Button>
            </form>

            <p className="text-caption text-text-tertiary">© AiClinic Health Group</p>
          </div>
        </div>

        <div className="relative hidden min-h-[420px] flex-col items-start justify-end overflow-hidden lg:flex">
          <img
            src={testimonials[currentTestimonial].image}
            alt=""
            className="absolute inset-0 size-full object-cover"
          />
          <div className="relative z-10 w-full bg-linear-to-t from-black/45 to-black/0 p-6 pt-20">
            <div className="flex h-max flex-col gap-6 overflow-hidden rounded-2xl bg-black/25 px-5 py-5 ring-1 ring-white/30 backdrop-blur-md ring-inset">
              <AnimatePresence initial={false} mode="popLayout" custom={direction}>
                <motion.blockquote
                  key={count}
                  custom={direction}
                  variants={carouselVariants}
                  initial="enter"
                  animate="center"
                  exit="exit"
                  transition={{ ...carouselTransition, delay: 0.02 }}
                  className="text-h2 text-balance text-white"
                >
                  {testimonials[currentTestimonial].quote}
                </motion.blockquote>
              </AnimatePresence>

              <div className="flex flex-col gap-3">
                <div className="flex flex-row items-start justify-between gap-4">
                  <AnimatePresence initial={false} mode="popLayout" custom={direction}>
                    <motion.p
                      key={`name-${count}`}
                      custom={direction}
                      variants={carouselVariants}
                      initial="enter"
                      animate="center"
                      exit="exit"
                      transition={{ ...carouselTransition, delay: 0.04 }}
                      className="text-title whitespace-nowrap text-white"
                    >
                      {testimonials[currentTestimonial].name}
                    </motion.p>
                  </AnimatePresence>

                  <div aria-hidden className="hidden gap-0.5 md:flex">
                    {Array.from({ length: 5 }).map((_, index) => (
                      <Star key={index} className="size-4 fill-white text-white" />
                    ))}
                  </div>
                </div>

                <div className="flex w-full flex-row items-end gap-3">
                  <AnimatePresence initial={false} mode="popLayout" custom={direction}>
                    <motion.div
                      key={`meta-${count}`}
                      custom={direction}
                      variants={carouselVariants}
                      initial="enter"
                      animate="center"
                      exit="exit"
                      transition={{ ...carouselTransition, delay: 0.05 }}
                      className="flex min-w-0 flex-1 flex-col gap-1"
                    >
                      <p className="text-body-strong whitespace-nowrap text-white">
                        {testimonials[currentTestimonial].title}
                      </p>
                      <p className="text-body-sm whitespace-nowrap text-white/85">
                        {testimonials[currentTestimonial].organization}
                      </p>
                    </motion.div>
                  </AnimatePresence>

                  <div className="flex shrink-0 gap-2">
                    <button
                      type="button"
                      aria-label="Previous testimonial"
                      onClick={() => navigateCarousel(-1)}
                      className="focus-ring group flex size-11 cursor-pointer items-center justify-center rounded-full border border-white/50 transition duration-100 ease-linear hover:border-white/70"
                    >
                      <ArrowLeft className="size-5 text-white transition-opacity group-hover:opacity-70" />
                    </button>
                    <button
                      type="button"
                      aria-label="Next testimonial"
                      onClick={() => navigateCarousel(1)}
                      className="focus-ring group flex size-11 cursor-pointer items-center justify-center rounded-full border border-white/50 transition duration-100 ease-linear hover:border-white/70"
                    >
                      <ArrowRight className="size-5 text-white transition-opacity group-hover:opacity-70" />
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </motion.div>
    </div>,
    document.body,
  )
}
