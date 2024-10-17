import { createClient } from '@/lib/supabase/server'
import { PostItem } from '@/components/PostItem'


export const revalidate = 60

export default async function Posts() {
    const client = createClient()
    const { data: posts } = await client.from('posts').select('*')

    console.log(posts)

    return (
        <div className="w-full font-thin text-2xl m-24">

            <UserMessage /> 

        <div className="flex flex-wrap gap-2 mt-24 text-xl">
        { posts!.map((post) => (
        <PostItem key={post.id} post={post}/>
        )) }
        </div>
        </div>

)
}

function UserMessage () {
    return (<>
    <div className="flex font-extrabold">
        Zarathustra!
    </div>
    <div className="flex mt-2 font-thin text-lg">
        You have discovered my trove of mental concoctions
    </div>
    <div className="flex mt-4 font-thin text-sm">
    <kbd>
        Hint: press command + k to navigate the wine-dark sea of ideas.
    </kbd>
    </div>
</>
)
}