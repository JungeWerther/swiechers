import { CMSContent } from "@/types/basic";

export const content: CMSContent = {
  app: [
    {
      title: "Seb Wiechers",
      description: "Data Wizard, Software Engineer, Entrepreneur",
      content: '## "Attention for people, passion for technology"',
      link: "/bio",
    },
    {
      title: "Data Projects",
      description: "AI, Machine Learning, Data Analysis",
      content:
        "Learn how I saved a client 1 FTE by training a classification model from scratch, achieving 95% accuracy.",
      link: "/projects",
    },
    {
      title: "Software Solutions",
      description: "Fullstack Development, AI engineering",
      content:
        "Read my take on web development, functional programming, AI, and more.",
      link: "/software",
    },
    {
      title: "Ruthless Tech Philosophy",
      description: "Bleeding edge blog on tech, business, and life",
      content: "Opinionated expositions - Only for the brave.",
      link: "/blog",
    },
  ],
  bio: [
    {
      title: "Seb Wiechers",
      description: "Data Wizard, Software Engineer, Entrepreneur",
      content: `## Why should you work with me?\n
- **Highly skilled.** _I write DRY, SOLID, clean, maintainable, and scalable code._
- **Emphatic team player.** _I am a great communicator and understand different stakeholders' needs._
- **Business acumen.** _I understand the business side of things and can translate business requirements into technical solutions._
      `,
    },
    {
      title: "Education",
      description:
        "Strong combination of rigid formal education and skills obtained in the field",
      content: `Understanding problems from first-principles pays off in the long run. I have a strong foundation in mathematics, statistics, and computer science, logic, and critical thinking.\n
## My education:
- University of St. Andrews, Grad. Dip. Philosophy _(emphasis on philosophy of logic)_
- University of Utrecht, Bsc. Mathematics
- University of Utrecht, Bsc. Physics & Astronomy
     `,
    },
    {
      title: "Experience",
      description: "Years of experience in the field",
      content: `Multiple years experience working for clients in various industries, particularly in Retail and for the cultural sector. \n
## Projects include:
- Training a classification model from scratch for an international retailer, achieving 95% accuracy, saving 1 FTE.
- 3D AI product customizer, allowing customers to design their own products with natural language.
- Sound sample generator, applying commutative algebra to spectral analysis.
- Variety of web development projects.
- Data engineering and analysis for a client in the cultural sector.
- Data analysis for a large retail client.
`,
      link: "/projects",
    },
  ],
};
