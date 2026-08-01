import { useState } from 'react'
import { Pagination } from '@/components/navigation/Pagination'
import { ShowcaseDemo, ShowcaseSection } from '../../ShowcasePrimitives'

export function PaginationShowcase() {
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(50)

  return (
    <ShowcaseSection
      id="pagination"
      title="Pagination"
      description="Page controls with tabular range summary and page-size select."
      componentName="Pagination"
    >
      <ShowcaseDemo label="Default" propsHint="page + pageSize + total">
        <Pagination
          page={page}
          pageSize={pageSize}
          total={2000}
          onPageChange={setPage}
          onPageSizeChange={setPageSize}
          className="w-full"
        />
      </ShowcaseDemo>
    </ShowcaseSection>
  )
}
