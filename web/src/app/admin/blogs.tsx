"use client";

import AdminNav from "@/components/admin-nav";
import AdminForm from "@/components/admin-form";
import { store } from "@/lib/store";

export default function AdminBlogs() {
  return (
    <main className="min-h-screen pt-24 px-6">
      <AdminNav />
      <h1 className="text-2xl font-bold mb-6">Blogs</h1>

      <AdminForm
        fields={[
          { name: "title", placeholder: "Title" },
          { name: "excerpt", placeholder: "Excerpt" }
        ]}
        onSubmit={data => {
          store.blogs.push({
            id: Date.now().toString(),
            title: data.title,
            excerpt: data.excerpt,
            date: new Date().toISOString().split("T")[0]
          });
        }}
      />
    </main>
  );
}
