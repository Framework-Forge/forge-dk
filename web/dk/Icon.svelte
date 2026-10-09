<script>
  export let name = 'document';
  const paths = {
    general: ['M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8', 'M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2M17 7l2-2'],
    types: ['M6 3h9l4 4v14H5V3h1', 'M14 3v5h5M8 12h8M8 16h6'],
    npcs: ['M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8', 'M5 21v-2a7 7 0 0 1 14 0v2'],
    records: ['M4 5h16v15H4zM4 9h16M9 9v11M13 13h4M13 16h4'],
    menu: ['M4 6h16M4 12h16M4 18h16'],
    close: ['m6 6 12 12M6 18 18 6'],
    plus: ['M12 5v14M5 12h14'],
    save: ['M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h12l4 4v12a2 2 0 0 1-2 2', 'M7 3v6h10V3M7 21v-7h10v7'],
    trash: ['M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7'],
    chevron: ['m9 5 7 7-7 7'],
    document: ['M6 3h9l4 4v14H5V3h1', 'M14 3v5h5M8 12h8M8 16h6'],
    brand: ['m12 2 10 10-10 10L2 12Z', 'm7 12 5-5 5 5-5 5Z'],
    warning: ['m12 3 10 18H2L12 3ZM12 9v5M12 17h.01'],
  };
</script>
<svg class="forge-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#each paths[name] || paths.document as path}<path d={path} />{/each}
</svg>
