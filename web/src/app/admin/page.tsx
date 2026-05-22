import AdminNav from "@/components/admin-nav";

export default function AdminPage() {
  return (
    <main className="min-h-screen pt-24 px-6">
      <AdminNav />
      <h1 className="text-3xl font-bold mb-4">Admin Dashboard</h1>
      <p className="text-gray-400">
        Manage projects and blog posts.
      </p>
    </main>
  );
}
