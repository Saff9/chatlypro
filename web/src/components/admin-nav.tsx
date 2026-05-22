import Link from "next/link";

export default function AdminNav() {
  return (
    <nav className="flex gap-6 mb-10 text-sm">
      <Link href="/admin">Dashboard</Link>
      <Link href="/admin/projects">Projects</Link>
      <Link href="/admin/blogs">Blogs</Link>
    </nav>
  );
}
