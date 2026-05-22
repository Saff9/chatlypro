export const dynamic = "force-static";

import Hero from "@/components/hero";
import Projects from "@/components/projects";
import Blog from "@/components/blog";

export default function HomePage() {
  return (
    <main>
      <Hero />
      <Projects />
      <Blog />
    </main>
  );
}
