export default {
  mounted() {
    this.handler = (e) => {
      const keys = ['j', 'k', 'w', 'b', ' '];
      if (keys.includes(e.key)) {
        e.preventDefault();
        this.pushEvent('key_nav', { key: e.key === ' ' ? 'space' : e.key });
      }
    };
    window.addEventListener('keydown', this.handler);
  },
  destroyed() {
    window.removeEventListener('keydown', this.handler);
  }
};
