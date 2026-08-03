import { useId, useState } from 'react'
import { FileDropzone, FormField, type FileItem } from '@/components/ui'
import { ShowcaseSection } from '../../ShowcasePrimitives'

export function FileDropzoneShowcase() {
  const id = useId()
  const [files, setFiles] = useState<FileItem[]>([])

  return (
    <ShowcaseSection
      id="file-dropzone"
      title="File dropzone"
      componentName="FileDropzone"
      description="Drag-over, browse, per-file progress, success/error, and remove."
    >
      <FormField
        id={id}
        label="Patient attachments"
        helperText="PDF, JPG, or PNG lab reports and scans."
      >
        <FileDropzone id={id} files={files} onFilesChange={setFiles} />
      </FormField>
    </ShowcaseSection>
  )
}
