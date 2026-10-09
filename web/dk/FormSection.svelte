<script>
  export let title;
  export let description = '';
</script>
<section class="form-section">
  <div class="form-section-heading"><h3>{title}</h3>{#if description}<small>{description}</small>{/if}</div>
  <div class="form-section-body"><slot /></div>
</section>
