import { MOCK_ORG } from '@/components/navigation/nav-model'
import { defaultWorkingSchedule } from './working-schedule'
<<<<<<< HEAD
import type { BranchRecord, OrganizationProfile, StaffRecord } from './types'
=======
import type { BranchRecord, OrganizationProfile, ServiceRecord, StaffRecord } from './types'
>>>>>>> master

export const INITIAL_ORGANIZATION: OrganizationProfile = {
  name: MOCK_ORG,
  logoUrl: null,
  currencyCode: 'EGP',
  timezone: 'Africa/Cairo',
}

export const INITIAL_BRANCHES: BranchRecord[] = [
  {
    id: 'downtown',
    name: 'Downtown Clinic',
    code: 'DTN',
    address: '12 Tahrir Square, Cairo',
    phone: '20223456789',
    mapsUrl: 'https://maps.google.com/?q=Tahrir+Square',
    isActive: true,
    workingSchedule: defaultWorkingSchedule(),
  },
  {
    id: 'nasr-city',
    name: 'Nasr City',
    code: 'NSR',
    address: '45 Abbas El Akkad St, Nasr City',
    phone: '20224567890',
    mapsUrl: 'https://maps.google.com/?q=Abbas+El+Akkad',
    isActive: true,
    workingSchedule: defaultWorkingSchedule(),
  },
  {
    id: 'alexandria',
    name: 'Alexandria',
    code: 'ALX',
    address: '8 Corniche Rd, Alexandria',
    phone: '20333456789',
    mapsUrl: 'https://maps.google.com/?q=Alexandria+Corniche',
    isActive: false,
    workingSchedule: defaultWorkingSchedule(),
  },
]

export const INITIAL_STAFF: StaffRecord[] = [
  {
    id: 'staff-1',
    fullName: 'Dr. Sarah Ali',
    phone: '201012345678',
    username: 'sarah.ali',
    role: 'doctor',
    branchIds: ['downtown', 'nasr-city'],
    primaryBranchId: 'downtown',
    isActive: true,
  },
  {
    id: 'staff-2',
    fullName: 'Ahmed Hassan',
    phone: '201098765432',
    username: 'ahmed.hassan',
    role: 'administrator',
    branchIds: ['downtown', 'nasr-city', 'alexandria'],
    primaryBranchId: 'downtown',
    isActive: true,
  },
  {
    id: 'staff-3',
    fullName: 'Mona El-Sayed',
    phone: '201055512345',
    username: 'mona.elsayed',
    role: 'receptionist',
    branchIds: ['downtown'],
    primaryBranchId: 'downtown',
    isActive: true,
  },
  {
    id: 'staff-4',
    fullName: 'Youssef Kamal',
    phone: '201066678901',
    username: 'youssef.kamal',
    role: 'lab_staff',
    branchIds: ['nasr-city'],
    primaryBranchId: 'nasr-city',
    isActive: true,
  },
]
<<<<<<< HEAD
=======

export const INITIAL_SERVICES: ServiceRecord[] = [
  {
    id: 'svc-consult',
    name: 'General consultation',
    price: 350,
    allBranches: true,
    branchIds: [],
  },
  {
    id: 'svc-cleaning',
    name: 'Dental cleaning',
    price: 500,
    allBranches: false,
    branchIds: ['downtown', 'nasr-city'],
  },
  {
    id: 'svc-xray',
    name: 'X-ray imaging',
    price: 200,
    allBranches: false,
    branchIds: ['downtown'],
  },
]
>>>>>>> master
