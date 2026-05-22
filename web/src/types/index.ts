export interface Project {
  id: string;
  title: string;
  description: string;
  link?: string;
}

export interface BlogPost {
  id: string;
  title: string;
  excerpt: string;
  date: string;
}
