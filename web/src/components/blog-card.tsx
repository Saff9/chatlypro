import { BlogPost } from "@/types";

export default function BlogCard({ post }: { post: BlogPost }) {
  return (
    <div className="border border-white/10 rounded-2xl p-6 hover:border-primary transition">
      <h3 className="text-xl font-semibold mb-2">
        {post.title}
      </h3>
      <p className="text-gray-400 text-sm mb-4">
        {post.excerpt}
      </p>
      <span className="text-xs text-gray-500">
        {post.date}
      </span>
    </div>
  );
}
