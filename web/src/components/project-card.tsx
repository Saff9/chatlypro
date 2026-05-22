import { Project } from "@/types";

export default function ProjectCard({ project }: { project: Project }) {
  return (
    <div className="rounded-2xl border border-white/10 p-6 hover:border-primary transition">
      <h3 className="text-xl font-semibold mb-2">
        {project.title}
      </h3>
      <p className="text-gray-400 text-sm mb-4">
        {project.description}
      </p>
      {project.link && (
        <a
          href={project.link}
          className="text-primary text-sm"
        >
          View →
        </a>
      )}
    </div>
  );
}
