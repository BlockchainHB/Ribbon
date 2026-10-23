# Framework choice

Decision, 21 October 2026: Astro, statically generated.

Ribbon's site is a product presentation with a small amount of interaction. Page load cost and shipped JavaScript matter more here than a server request benchmark or a large application rendering benchmark. There is no universal fastest framework across those workloads.

| Framework | Relevant behavior | Fit here |
| --- | --- | --- |
| [Astro](https://docs.astro.build/en/concepts/islands/) | Components render to static HTML with no browser framework runtime by default. Optional JavaScript is added explicitly. | Selected: component-based authoring, static output, small interaction scripts. |
| [SvelteKit](https://svelte.dev/docs/kit/page-options#csr) | Can prerender pages and disable client rendering to ship zero JavaScript. | Also capable; its application routing and client rendering are not needed for this site. |
| [Qwik](https://qwik.dev/docs/concepts/resumable/) | Serializes server-rendered state and resumes interaction without conventional hydration. | Useful for more interactive applications; not an advantage over plain HTML for this page's static content. |
| [Next.js](https://nextjs.org/docs/app/guides/static-exports) | Supports static exports and build-time Server Components. | Capable, but this site does not need its React application model. |

This is a fit decision based on architecture, not a claim that a four-framework benchmark was run. Measure this site's actual production output and browser behavior. No client framework, animation library, external font, or third-party widget is needed. DataFast analytics was added later, on 22 October 2026, as a single deferred script tag (see README).

Versions are pinned in package.json and the dependency tree is locked. Sources were checked live; raw research is in the gitignored `.firecrawl/framework-choice/` directory at the repository root.
