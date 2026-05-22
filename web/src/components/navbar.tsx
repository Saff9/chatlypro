import Link from "next/link";

export default function Navbar() {
  return (
    <nav className="fixed top-0 w-full z-50 bg-black/40 backdrop-blur">
      <div className="max-w-6xl mx-auto px-4 h-16 flex items-center justify-between">
        <Link href="/" className="font-bold text-lg">
          GenZ Owais
        </Link>
        <div className="space-x-6 text-sm">
          <Link href="#projects">Projects</Link>
          <Link href="#blog">Blog</Link>
          <Link href="/admin">Admin</Link>
        </div>
      </div>
    </nav>
  );
}
