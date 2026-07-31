import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../src', import.meta.url))

function walk(dir, files = []) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) {
      walk(path, files)
    } else if (path.endsWith('.tsx') || path.endsWith('.ts')) {
      files.push(path)
    }
  }
  return files
}

const files = walk(root)
const sourceByFile = Object.fromEntries(
  files.map((file) => [file, readFileSync(file, 'utf8')]),
)
const allSource = Object.values(sourceByFile).join('\n')

function hasDomId(id) {
  const quoted = new RegExp(`id=["']${id}["']`)
  const braced = new RegExp(`id=\\{["']${id}["']\\}`)
  return quoted.test(allSource) || braced.test(allSource)
}

const foundationSections = ['colors', 'typography', 'spacing', 'motion', 'signal']
const groupIds = ['actions', 'inputs', 'display', 'navigation', 'feedback', 'ai', 'layout']

const registryFiles = [
  'showcase/components/actions/index.ts',
  'showcase/components/inputs/index.ts',
  'showcase/components/display/index.ts',
  'showcase/components/navigation/index.ts',
  'showcase/components/feedback/index.ts',
  'showcase/components/ai/index.ts',
  'showcase/components/layout/index.ts',
]

const patternIndex = readFileSync(join(root, 'showcase/patterns/index.ts'), 'utf8')
const patternIds = [...patternIndex.matchAll(/id:\s*['"]([^'"]+)['"]/g)].map((m) => m[1])

const guidelinesIndex = readFileSync(join(root, 'showcase/guidelines/AccessibilityGuidelinesShowcase.tsx'), 'utf8')
const guidelineIds = [
  'guidelines-voice',
  ...[...guidelinesIndex.matchAll(/id=["']([^"']+)["']/g)].map((m) => m[1]),
]

const sectionIds = registryFiles.flatMap((relativePath) => {
  const content = readFileSync(join(root, relativePath), 'utf8')
  return [...content.matchAll(/id:\s*['"]([^'"]+)['"]/g)].map((match) => match[1])
})

const componentsPage = readFileSync(join(root, 'pages/ComponentsPage.tsx'), 'utf8')
const hasDynamicGroupAnchors = componentsPage.includes('id={`group-${group.id}`}')

const navTargets = [
  ...foundationSections,
  ...groupIds.map((group) => `group-${group}`),
  ...sectionIds,
  ...patternIds,
  ...guidelineIds,
]

const missing = []
for (const id of navTargets) {
  if (id.startsWith('group-')) {
    if (!hasDynamicGroupAnchors && !hasDomId(id)) {
      missing.push(id)
    }
    continue
  }
  if (!hasDomId(id)) {
    missing.push(id)
  }
}

if (missing.length > 0) {
  console.error('Missing DOM ids for dev nav targets:')
  for (const id of missing) {
    console.error(`  - ${id}`)
  }
  process.exit(1)
}

console.log(`Validated ${navTargets.length} dev nav targets.`)
