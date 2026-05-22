import { getProjects } from "../lib/data";
import ProjectCard from "./project-card";
import Reveal from "./reveal";

export default async function Projects() {
  const projects = await getProjects();

  return (
    <section
      id="projects"
      className="max-w-6xl mx-auto px-4 py-24"
    >
      <h2 className="text-3xl font-bold mb-10">Projects</h2>

      <div className="grid gap-6 sm:grid-cols-2">
        {projects.map(project => (
          <Reveal key={project.id}>
            <ProjectCard project={project} />
          </Reveal>
        ))}
      </div>
    </section>
  );
}
