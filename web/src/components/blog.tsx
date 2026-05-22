import { getBlogs } from "../lib/data";
import BlogCard from "./blog-card";
import Reveal from "./reveal";


export default async function Blog() {
  const posts = await getBlogs();

  return (
    <section
      id="blog"
      className="max-w-6xl mx-auto px-4 py-24"
    >
      <h2 className="text-3xl font-bold mb-10">
        Blog
      </h2>

      <div className="grid gap-6 sm:grid-cols-2">
        {posts.map(post => (
          <Reveal key={post.id}>
            <BlogCard post={post} />
          </Reveal>
        ))}
      </div>
    </section>
  );
}
