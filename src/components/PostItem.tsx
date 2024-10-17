import { Card, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Database } from '@/types/database.types'

import Link from 'next/link'

type Post = Database['public']['Tables']['posts']['Row']

export function PostItem ({post}: {post: Post} ) {
    return (
        <Link href={`/ideas/${post.slug}`}>
            <Card className='bg-slate-100 hover:bg-black hover:text-white'>
            <CardHeader>
                <CardTitle>
                    {post.title}
                </CardTitle>
                <CardDescription>
                    {niceTimeZone(post.created_at)}
                    <br/>
                    {post.tagline}

                </CardDescription>
                </CardHeader>

                {/* <CardContent>
                    
                 </CardContent> */}
                <CardFooter>
                <div className="flex flex-wrap justify-start">
                {post.tags?.map(
                        (tag, i) => <div key={i} className={`
                            px-3 
                            text-white 
                            py-0.5 
                            font-sm 
                            ${randomTailwindColor()}
                            ${i == 0 && 'rounded-l-lg'}
                            ${i + 1 == post.tags?.length && 'rounded-r-lg'}
                            grow
                            mt-1
                            `}>
                            {tag}
                        </div>
                    )}
                    </div>
                </CardFooter>
            </Card>
        </Link>
    )
}

function randomTailwindColor() {
    const options = [
        "bg-red-400",
        "bg-blue-400",
        "bg-green-400",
        "bg-yellow-400",
        "bg-purple-400",
        "bg-pink-400",
        "bg-indigo-400",
        "bg-gray-400",
        "bg-orange-400",
        "bg-teal-400",
        "bg-cyan-400",
        "bg-lime-400",
        "bg-amber-400",
        "bg-emerald-400",
        "bg-fuchsia-400",
        "bg-rose-400"
    ]

    return options[Math.floor(Math.random() * options.length)]
}

function niceTimeZone(isostring: string) {
    return new Date(isostring).toLocaleDateString()
}