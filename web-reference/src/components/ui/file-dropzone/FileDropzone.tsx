import { AlertCircle, CheckCircle2, FileText, Upload, X } from 'lucide-react'
import { useCallback, useId, useRef, useState } from 'react'
import { cn } from '@/lib/cn'
import { Spinner } from '../spinner/Spinner'

export type FileItem = {
  id: string
  name: string
  size: number
  status: 'uploading' | 'success' | 'error'
  progress?: number
  error?: string
}

export type FileDropzoneProps = {
  id?: string
  accept?: string
  multiple?: boolean
  disabled?: boolean
  invalid?: boolean
  files?: FileItem[]
  onFilesChange?: (files: FileItem[]) => void
  onUpload?: (file: File) => Promise<void>
  maxSizeMb?: number
  className?: string
  'aria-labelledby'?: string
  'aria-describedby'?: string
}

function formatSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function FileDropzone({
  id: idProp,
  accept = '.pdf,.jpg,.jpeg,.png',
  multiple = true,
  disabled,
  invalid,
  files: controlled,
  onFilesChange,
  onUpload,
  maxSizeMb = 10,
  className,
  ...aria
}: FileDropzoneProps) {
  const autoId = useId()
  const id = idProp ?? autoId
  const inputRef = useRef<HTMLInputElement>(null)
  const [dragOver, setDragOver] = useState(false)
  const [internal, setInternal] = useState<FileItem[]>([])

  const files = controlled ?? internal
  const setFiles = (next: FileItem[]) => {
    if (controlled === undefined) setInternal(next)
    onFilesChange?.(next)
  }

  const processFiles = useCallback(
    async (fileList: FileList | null) => {
      if (!fileList) return
      const incoming = Array.from(fileList)
      for (const file of incoming) {
        if (file.size > maxSizeMb * 1024 * 1024) {
          const item: FileItem = {
            id: crypto.randomUUID(),
            name: file.name,
            size: file.size,
            status: 'error',
            error: `File exceeds ${maxSizeMb} MB limit`,
          }
          setFiles([...files, item])
          continue
        }
        const item: FileItem = {
          id: crypto.randomUUID(),
          name: file.name,
          size: file.size,
          status: 'uploading',
          progress: 0,
        }
        const next = [...files, item]
        setFiles(next)

        if (onUpload) {
          try {
            // Simulate progress for showcase
            for (let p = 20; p <= 100; p += 20) {
              await new Promise((r) => setTimeout(r, 200))
              setFiles(
                next.map((f) => (f.id === item.id ? { ...f, progress: p } : f)),
              )
            }
            await onUpload(file)
            setFiles(
              next.map((f) =>
                f.id === item.id ? { ...f, status: 'success', progress: 100 } : f,
              ),
            )
          } catch {
            setFiles(
              next.map((f) =>
                f.id === item.id
                  ? { ...f, status: 'error', error: 'Upload failed. Try again.' }
                  : f,
              ),
            )
          }
        } else {
          await new Promise((r) => setTimeout(r, 800))
          setFiles(
            next.map((f) =>
              f.id === item.id ? { ...f, status: 'success', progress: 100 } : f,
            ),
          )
        }
      }
    },
    [files, maxSizeMb, onUpload, setFiles],
  )

  const remove = (fileId: string) => {
    setFiles(files.filter((f) => f.id !== fileId))
  }

  return (
    <div className={cn('flex flex-col gap-3', className)}>
      <div
        role="button"
        tabIndex={disabled ? -1 : 0}
        aria-disabled={disabled}
        aria-invalid={invalid || undefined}
        onDragOver={(e) => {
          e.preventDefault()
          if (!disabled) setDragOver(true)
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault()
          setDragOver(false)
          if (!disabled) void processFiles(e.dataTransfer.files)
        }}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            inputRef.current?.click()
          }
        }}
        className={cn(
          'flex flex-col items-center gap-3 rounded-lg border-2 border-dashed p-8 text-center transition-colors',
          dragOver
            ? 'border-border-focus bg-surface-selected'
            : 'border-border-default bg-surface-default',
          invalid && 'border-status-danger-border',
          disabled && 'cursor-not-allowed opacity-50',
          !disabled && 'cursor-pointer hover:bg-surface-hover',
        )}
        onClick={() => !disabled && inputRef.current?.click()}
        {...aria}
      >
        <Upload className="size-8 text-icon-muted" aria-hidden />
        <div>
          <p className="text-body-strong text-text-primary">Drop files here</p>
          <p className="mt-1 text-caption text-text-tertiary">
            PDF, JPG, PNG up to {maxSizeMb} MB
          </p>
        </div>
        <button
          type="button"
          disabled={disabled}
          className="focus-ring rounded-md border border-border-default bg-surface-default px-4 py-2 text-body-strong hover:bg-surface-hover disabled:opacity-50"
          onClick={(e) => {
            e.stopPropagation()
            inputRef.current?.click()
          }}
        >
          Browse files
        </button>
        <input
          ref={inputRef}
          id={id}
          type="file"
          accept={accept}
          multiple={multiple}
          disabled={disabled}
          className="sr-only"
          onChange={(e) => void processFiles(e.target.files)}
        />
      </div>

      {files.length > 0 ? (
        <ul className="flex flex-col gap-2" aria-label="Uploaded files">
          {files.map((file) => (
            <li
              key={file.id}
              className="flex items-center gap-3 rounded-md border border-border-subtle bg-surface-default px-3 py-2"
            >
              <FileText className="size-5 shrink-0 text-icon-muted" aria-hidden />
              <div className="min-w-0 flex-1">
                <p className="truncate text-body text-text-primary">{file.name}</p>
                <p className="text-caption text-text-tertiary tabular-nums">
                  {formatSize(file.size)}
                </p>
                {file.status === 'uploading' && file.progress !== undefined ? (
                  <div className="mt-1 h-1 overflow-hidden rounded-full bg-surface-muted">
                    <div
                      className="h-full bg-action-primary transition-[width] duration-[var(--duration-base)]"
                      style={{ width: `${file.progress}%` }}
                      role="progressbar"
                      aria-valuenow={file.progress}
                      aria-valuemin={0}
                      aria-valuemax={100}
                    />
                  </div>
                ) : null}
                {file.error ? (
                  <p className="mt-0.5 text-caption text-status-danger-fg">{file.error}</p>
                ) : null}
              </div>
              {file.status === 'uploading' ? (
                <Spinner size="sm" />
              ) : file.status === 'success' ? (
                <CheckCircle2 className="size-5 shrink-0 text-status-success-fg" aria-label="Upload complete" />
              ) : file.status === 'error' ? (
                <AlertCircle className="size-5 shrink-0 text-status-danger-fg" aria-label="Upload failed" />
              ) : null}
              <button
                type="button"
                onClick={() => remove(file.id)}
                className="focus-ring rounded-sm p-1 text-icon-muted hover:text-icon-default"
                aria-label={`Remove ${file.name}`}
              >
                <X className="size-4" />
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  )
}
