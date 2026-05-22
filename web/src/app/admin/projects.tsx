"use client";

import AdminNav from "@/components/admin-nav";
import AdminForm from "@/components/admin-form";
import { store } from "@/lib/store";

export default function AdminProjects() {
  return (
    <main className="min-h-screen pt-24 px-6">
      <AdminNav />
      <h1 className="text-2xl font-bold mb-6">Projects</h1>

      <AdminForm
        fields={[
          { name: "title", placeholder: "Title" },
          { name: "description", placeholder: "Description" }
        ]}
        onSubmit={data => {
          store.projects.push({
            id: Date.now().toString(),
            title: data.title,
            description: data.description
          });
        }}
      />
    </main>
  );
}
