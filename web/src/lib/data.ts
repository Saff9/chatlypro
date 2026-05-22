import { Project, BlogPost } from "@/types";

export async function getProjects(): Promise<Project[]> {
  return [
    {
      id: "1",
      title: "CampusConnect",
      description: "A student networking platform built for scale.",
      link: "#"
    },
    {
      id: "2",
      title: "GenZ Portfolio",
      description: "High-performance personal brand website.",
      link: "#"
    }
  ];
}

export async function getBlogs(): Promise<BlogPost[]> {
  return [
    {
      id: "1",
      title: "How I Build Fast Websites",
      excerpt: "A breakdown of performance-first architecture.",
      date: "2025-01-10"
    },
    {
      id: "2",
      title: "Why Most Portfolios Are Slow",
      excerpt: "And how to fix them the right way.",
      date: "2025-01-05"
    }
  ];
}
