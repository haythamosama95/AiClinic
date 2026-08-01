import { useState } from 'react'
import { motion } from 'motion/react'
import { Tabs } from '@/components/navigation/Tabs'
import { motionPresets, resolveTransition } from '@/lib/motion'
import type { Appointment, Doctor } from '../types'
import { CheckedInPanel } from './CheckedInPanel'
import { DoctorsPanel } from './DoctorsPanel'

type FlowControlPanelProps = {
  patients: Appointment[]
  doctors: Doctor[]
  appointments: Appointment[]
  now: number
}

type FlowTab = 'waiting' | 'doctors'

export function FlowControlPanel({ patients, doctors, appointments, now }: FlowControlPanelProps) {
  const [activeTab, setActiveTab] = useState<FlowTab>('waiting')

  return (
    <section
      className="h-auto self-start overflow-hidden rounded-xl border border-border-default bg-surface-default"
      aria-label="Flow control"
    >
      <div className="border-b border-border-default px-3 pt-3">
        <Tabs
          variant="underline"
          equalWidth
          aria-label="Flow control sections"
          items={[
            { id: 'waiting', label: `Waiting (${patients.length})` },
            { id: 'doctors', label: `Doctors (${doctors.length})` },
          ]}
          value={activeTab}
          onChange={(id) => setActiveTab(id as FlowTab)}
        />
      </div>

      <motion.div className="h-auto" layout transition={resolveTransition(motionPresets.collapse)}>
        {activeTab === 'waiting' ? (
          <div role="tabpanel" aria-label="Checked-in patients waiting">
            <CheckedInPanel patients={patients} now={now} embedded />
          </div>
        ) : (
          <div role="tabpanel" aria-label="Doctors on shift">
            <DoctorsPanel doctors={doctors} appointments={appointments} now={now} embedded />
          </div>
        )}
      </motion.div>
    </section>
  )
}
