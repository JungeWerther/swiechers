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
  projects: [
    {
      title: "Classification of semi-structured data (AWS and GCP)",
      description: "Retail client",
      content: `## Training, testing, deploying\n
The client had to manually classify incoming data from suppliers on a running basis, which was messy and structured in a different format each time. Combining semantic embeddings and classical machine learning methods, we were able to train a model that was able to cast line items into the correct category with 95% accuracy. This saved them 1 FTE.
      `,
    },
    {
      title: "Production-grade RAG pipeline",
      description: "Financial sector",
      content: `## Full-stack development, AI Engineering, DevOps\n
Developed a [production-grade RAG pipeline](https://pearstop.com) for use with internal documents, allowing for easy natural-language retrieval of information. Technologies used:
- React
- PostgreSQL
- Python
- AWS (Lambda, SQS, S3, Bedrock, ... 
- Docker
- Github Actions
- Terraform
`,
    },
    {
      title: "Data infrastructure for a large event organizer (Azure)",
      description: "Cultural sector",
      content: `## Data engineering and analysis\n
My client had a variety of software systems that were not connected. I configured ETL jobs into a cloud data warehouse, then configured a variety of dashboards which allowed them to track daily KPIs. This enabled data-driven decision making to identify areas of the business which carried disproportional cost, greatly increasing operational efficiency.
`,
    },
    {
      title: "3D AI product customizer",
      description: "E-commerce",
      content: `## Full-stack development\n
Developed a [multi-user web-app for customizing products with natural language](https://youtu.be/8WFgqzNZnsY?feature=shared&t=29), rendering them in 3D. Rendered customizations got mapped to manufacturer blueprint, ready for physical production. Technologies used:
- React
- Three.js
- PostgreSQL
`,
    },
  ],
  blog: [
    {
      title: "MeTTa language",
      description: "OpenCog Hyperon Neurosymbolic AI framework",
      content: `
For some months now, I've been learning the [MeTTa language](https://metta-lang.dev). I'm extremely excited about where this language is headed and believe that it has true potential.

Current LLM architecture is extremely good at generating generalist answers but fails to generalize beyond the training dataset. The reason is, that transformers architecture is geared to giving the probabilistically most likely anwer, based on curated input from its training data. 

This is not how humans think. Humans think in terms of concepts and relations between them.

In MeTTa, there is only one type of object: the **atom**. These atoms live in a **space**. For example

    (= (m) (Hello World)) 

will allow you to to call

    !(m) 

which will output \`[(Hello World)]\`. 

# Nothing crazy, right?
But now, define (m) again:
    
    (= (m) (Hello Another World))
    !(m)

and it will output \`[(Hello World), (Hello Another World)]\`. Non-deterministic output!

You can define functions and variables by prepending $, like so:
    
    (= (greet $m) (Hello $m))
    !(greet John) ; outputs [(Hello John)]

Interesting!

Now check out this code:

    (: M (-> $T Type))                                     
    (: mkM (-> $T (M $T)))         
    (: bind (-> (M $T) (-> $T $U) (M $U)))

    (= (bind (mkM $val) $func) (mkM ($func $val)))       
    
    (= ((mkM $val) $func) (mkM ($func $val)))        
    (= ((mkM $val) effect $func) (let $_ ($func $val)(mkM $val)))

    (: add1 (-> Number Number))
    (= (add1 $x) (+ $x 1))

    (= (m) (mkM 42))
    !(assertEqual ((m) effect add1) (mkM 42))               
    !(assertEqual ((m) add1) (mkM 43))                      

    ;-------                                                         

    (= (add-to-self $m $x) (add-atom &self ($m $x)))
    (= ((add-to-self $m) $x) (add-to-self $m $x))   
    (= ($m) (mkM (match &self ($m $f) $f)))
    (= (from ($s to $t) $func) ((($s) $func) effect (add-to-self $t)))


    (e 1)
    (e 2)
    (e 5)                                                   
    !(from (e to e1) add1)


    ;--------

    (= (remove-from-self $m $x) (remove-atom &self ($m $x)))
    (= ((remove-from-self $m) $x) (remove-from-self $m $x))
    (= (to $s $func) (((($s) effect (remove-from-self $s)) $func) effect (add-to-self $s)))

    !(to e1 add1)

    ;---------

    ;when you want to access the values directly

    (= (unwrap (mkM $b)) $b)                               
    (= (gimme $s) (unwrap ($s)))
    !(gimme e1)

What an elegant way to store and manipulate data!
`,
    },
  ],
};
