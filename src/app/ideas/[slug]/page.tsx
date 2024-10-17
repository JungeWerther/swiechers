import { createClient } from '@/lib/supabase/server'
import { isrClient } from '@/lib/supabase/isrclient'
import { notFound } from 'next/navigation'
import DOMPurify from 'dompurify'
import { JSDOM } from 'jsdom'
import { marked } from 'marked'
import styles from './Page.module.css'
import { PostItem } from '@/components/PostItem'

export const revalidate = 60

export async function generateStaticParams() {
  const client = isrClient()
  const { data: posts } = await client.from('posts').select('slug')

  return posts?.map(({ slug }) => ({
    slug,
  }))
}

export default async function Post({ params: { slug } }: { params: { slug: string } }) {
  const client = createClient()
  const { data: post } = await client.from('posts').select().match({ slug }).single()

  if (!post) {
    notFound()
  }

  return (
    <div className="m-24 gap-2 relative flex flex-row justify-between ">
    
    <div className="border-r border-l p-12 overflow-scroll w-full">
    <Rendermd markdown={post.markdown!} />
    </div>
    
    <PostItem post={post}/>
    </div>

  )
}

function Rendermd({markdown}:{markdown: string}) {
    const html = DOMPurify((new JSDOM("<!DOCTYPE html>")).window).sanitize(
        marked.parse(
           markdown, { async: false }
        )
    )

    return <div className={styles.markdown} dangerouslySetInnerHTML={{__html: html}} />
}