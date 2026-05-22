import { getBlogs } from "@/lib/data";
import BlogCard from "@/components/blog-card";

export default async function BlogPage() {
  const posts = await getBlogs();

  return (
    <main className="max-w-6xl mx-auto px-4 pt-24">
      <h1 className="text-4xl font-bold mb-12">
        Blog
      </h1>

      <div className="grid gap-6 sm:grid-cols-2">
        {posts.map(post => (
          <BlogCard key={post.id} post={post} />
        ))}
      </div>
    </main>
  );
}
