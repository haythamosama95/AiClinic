import { useCallback, useState } from 'react'
import {
  INITIAL_BRANCHES,
  INITIAL_ORGANIZATION,
<<<<<<< HEAD
  INITIAL_STAFF,
} from './mock-data'
import type { BranchRecord, OrganizationProfile, StaffRecord } from './types'
=======
  INITIAL_SERVICES,
  INITIAL_STAFF,
} from './mock-data'
import type { BranchRecord, OrganizationProfile, ServiceRecord, StaffRecord } from './types'
>>>>>>> master

export function useClinicManagementState() {
  const [organization, setOrganization] = useState<OrganizationProfile>(INITIAL_ORGANIZATION)
  const [branches, setBranches] = useState<BranchRecord[]>(INITIAL_BRANCHES)
  const [staff, setStaff] = useState<StaffRecord[]>(INITIAL_STAFF)
<<<<<<< HEAD
=======
  const [services, setServices] = useState<ServiceRecord[]>(INITIAL_SERVICES)
>>>>>>> master

  const updateOrganization = useCallback((next: OrganizationProfile) => {
    setOrganization(next)
  }, [])

  const addBranch = useCallback((branch: BranchRecord) => {
    setBranches((prev) => [...prev, branch])
  }, [])

  const updateBranch = useCallback((id: string, patch: Partial<BranchRecord>) => {
    setBranches((prev) => prev.map((b) => (b.id === id ? { ...b, ...patch } : b)))
  }, [])

  const removeBranch = useCallback((id: string) => {
    setBranches((prev) => prev.filter((b) => b.id !== id))
    setStaff((prev) =>
      prev
        .map((s) => {
          const branchIds = s.branchIds.filter((bid) => bid !== id)
          if (branchIds.length === 0) return null
          return {
            ...s,
            branchIds,
            primaryBranchId:
              s.primaryBranchId === id ? branchIds[0] ?? null : s.primaryBranchId,
          }
        })
        .filter((s): s is StaffRecord => s !== null),
    )
  }, [])

  const addStaff = useCallback((member: StaffRecord) => {
    setStaff((prev) => [...prev, member])
  }, [])

  const updateStaff = useCallback((id: string, patch: Partial<StaffRecord>) => {
    setStaff((prev) => prev.map((s) => (s.id === id ? { ...s, ...patch } : s)))
  }, [])

  const removeStaff = useCallback((id: string) => {
    setStaff((prev) => prev.filter((s) => s.id !== id))
  }, [])

<<<<<<< HEAD
=======
  const addService = useCallback((service: ServiceRecord) => {
    setServices((prev) => [...prev, service])
  }, [])

  const updateService = useCallback((id: string, patch: Partial<ServiceRecord>) => {
    setServices((prev) => prev.map((s) => (s.id === id ? { ...s, ...patch } : s)))
  }, [])

  const removeService = useCallback((id: string) => {
    setServices((prev) => prev.filter((s) => s.id !== id))
  }, [])

>>>>>>> master
  return {
    organization,
    branches,
    staff,
<<<<<<< HEAD
=======
    services,
>>>>>>> master
    updateOrganization,
    addBranch,
    updateBranch,
    removeBranch,
    addStaff,
    updateStaff,
    removeStaff,
<<<<<<< HEAD
=======
    addService,
    updateService,
    removeService,
>>>>>>> master
  }
}

export type ClinicManagementState = ReturnType<typeof useClinicManagementState>
