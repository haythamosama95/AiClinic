import { useCallback, useEffect, useMemo, useState } from 'react'
import { PageHeader } from '@/components/layout/PageHeader'
import { ROLES } from './mock-data'
import { releaseOverlayLocks } from './overlay-cleanup'
import type { CreateShiftInput } from './types'
import { useShiftsState } from './useShiftsState'
import { AssignStaffDialog } from './components/AssignStaffDialog'
import { CopyScheduleDialog } from './components/CopyScheduleDialog'
import { CreateShiftDialog } from './components/CreateShiftDialog'
import { DuplicateShiftDialog } from './components/DuplicateShiftDialog'
import { RoleSelector } from './components/RoleSelector'
import { ShiftCalendarEmpty } from './components/ShiftCalendarEmpty'
import { ShiftCalendarToolbar } from './components/ShiftCalendarToolbar'
import { ShiftCoverageStats } from './components/ShiftCoverageStats'
import { ShiftDetailDrawer } from './components/ShiftDetailDrawer'
import { ShiftMonthView } from './components/ShiftMonthView'
import { ShiftWeekView } from './components/ShiftWeekView'
import { StaffRosterPanel } from './components/StaffRosterPanel'
import './shifts.css'

export function ShiftsPage() {
  const {
    shifts,
    roleShifts,
    selectedRoleId,
    setSelectedRoleId,
    calendarView,
    setCalendarView,
    anchorDate,
    weekDays,
    coverage,
    selectedShift,
    selectedShiftId,
    setSelectedShiftId,
    assignShift,
    setAssignShiftId,
    createOpen,
    setCreateOpen,
    copyOpen,
    setCopyOpen,
    rosterSearch,
    setRosterSearch,
    roleStaff,
    createShift,
    copySchedule,
    assignStaff,
    navigateCalendar,
    goToToday,
    unassignStaff,
    deleteShift,
    duplicateShift,
    setDuplicateShiftId,
    duplicateShiftToDates,
    updateShiftHeadcount,
  } = useShiftsState()
  const [pendingStaffId, setPendingStaffId] = useState<string | null>(null)

  useEffect(() => () => releaseOverlayLocks(), [])

  const handleCreateShift = useCallback(
    (input: CreateShiftInput) => {
      setSelectedRoleId(input.roleId)
      setSelectedShiftId(null)
      setAssignShiftId(null)
      createShift(input)
      releaseOverlayLocks()
    },
    [createShift, setAssignShiftId, setSelectedRoleId, setSelectedShiftId],
  )

  const activeRole = ROLES.find((r) => r.id === selectedRoleId) ?? ROLES[0]

  const calendarTitle = useMemo(() => {
    if (calendarView === 'month') {
      return anchorDate.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
    }
    return `${weekDays[0].toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${weekDays[6].toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`
  }, [calendarView, anchorDate, weekDays])

  const handleAssignFromRoster = (staffId: string) => {
    setPendingStaffId(staffId)
    if (selectedShift) {
      setAssignShiftId(selectedShift.id)
    } else {
      setAssignShiftId(roleShifts[0]?.id ?? null)
    }
  }

  return (
    <div className="shifts-page">
      <PageHeader
        title="Shifts"
        description="Configure coverage, assign staff, and manage schedules across roles."
      />

      <div className="mt-6 space-y-5">
        <RoleSelector
          selectedRoleId={selectedRoleId}
          onSelect={setSelectedRoleId}
        />

        <ShiftCoverageStats
          coverage={coverage}
          accentClass={activeRole.accentClass}
        />

        <div className="shifts-layout grid gap-6 lg:grid-cols-[minmax(260px,280px)_1fr]">
          <StaffRosterPanel
            staff={roleStaff}
            shifts={shifts}
            weekDays={weekDays}
            search={rosterSearch}
            onSearchChange={setRosterSearch}
            onAssignToShift={handleAssignFromRoster}
          />

          <div className="min-w-0 space-y-4">
            <ShiftCalendarToolbar
              title={calendarTitle}
              view={calendarView}
              onViewChange={setCalendarView}
              onNavigate={navigateCalendar}
              onToday={goToToday}
              onCreateShift={() => setCreateOpen(true)}
              onCopySchedule={() => setCopyOpen(true)}
            />

            {roleShifts.length === 0 ? (
              <ShiftCalendarEmpty onCreateShift={() => setCreateOpen(true)} />
            ) : calendarView === 'week' ? (
              <ShiftWeekView
                weekDays={weekDays}
                shifts={roleShifts}
                selectedShiftId={selectedShiftId}
                onSelectShift={setSelectedShiftId}
                onAssignDrop={assignStaff}
                onDuplicateShift={setDuplicateShiftId}
                onDeleteShift={deleteShift}
              />
            ) : (
              <ShiftMonthView
                anchorDate={anchorDate}
                shifts={roleShifts}
                selectedShiftId={selectedShiftId}
                onSelectShift={setSelectedShiftId}
                onDuplicateShift={setDuplicateShiftId}
                onDeleteShift={deleteShift}
              />
            )}
          </div>
        </div>
      </div>

      <ShiftDetailDrawer
        open={selectedShift !== null}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedShiftId(null)
            releaseOverlayLocks()
          }
        }}
        shift={selectedShift}
        onAssign={() => setAssignShiftId(selectedShiftId)}
        onUnassign={(staffId) => {
          if (selectedShiftId) unassignStaff(selectedShiftId, staffId)
        }}
        onDelete={() => {
          if (selectedShiftId) deleteShift(selectedShiftId)
        }}
        onHeadcountChange={(headcount) => {
          if (selectedShiftId) updateShiftHeadcount(selectedShiftId, headcount)
        }}
      />

      <CreateShiftDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        defaultRoleId={selectedRoleId}
        onCreate={handleCreateShift}
      />

      <CopyScheduleDialog
        open={copyOpen}
        onOpenChange={setCopyOpen}
        currentRoleId={selectedRoleId}
        anchorDate={anchorDate}
        onCopy={copySchedule}
      />

      <DuplicateShiftDialog
        open={duplicateShift !== null}
        onOpenChange={(open) => {
          if (!open) {
            setDuplicateShiftId(null)
            releaseOverlayLocks()
          }
        }}
        shift={duplicateShift}
        onDuplicate={duplicateShiftToDates}
      />

      <AssignStaffDialog
        open={assignShift !== null}
        onOpenChange={(open) => {
          if (!open) {
            setAssignShiftId(null)
            setPendingStaffId(null)
            releaseOverlayLocks()
          }
        }}
        shift={assignShift}
        allShifts={shifts}
        preselectedStaffId={pendingStaffId}
        onAssign={(shiftId, staffId) => {
          assignStaff(shiftId, staffId)
          setPendingStaffId(null)
        }}
      />
    </div>
  )
}
