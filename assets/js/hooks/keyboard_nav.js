export default {
  mounted() {
    this.repeatIntervalMs = 60;
    this.lastNavAt = { w: 0, b: 0 };
    this.tokenEls = [];

    this.cacheTokens = () => {
      this.tokenEls = Array.from(this.el.querySelectorAll('.tokens-container .token'));
    };

    this.getSelectableIndices = () => {
      return this.tokenEls
        .filter((el) => el.dataset.selectable === 'true')
        .map((el) => Number(el.dataset.tokenIndex));
    };

    this.getFocusedIndex = () => {
      const focused = this.el.querySelector('.tokens-container .token-focused');
      return focused ? Number(focused.dataset.tokenIndex) : 0;
    };

    this.setFocusedIndex = (index) => {
      this.tokenEls.forEach((el) => {
        const tokenIndex = Number(el.dataset.tokenIndex);
        el.classList.toggle('token-focused', tokenIndex === index);
      });
    };

    this.moveFocusOptimistically = (key) => {
      this.cacheTokens();

      const selectable = this.getSelectableIndices();
      if (selectable.length === 0) return;

      const current = this.getFocusedIndex();
      let next;

      if (key === 'w') {
        next = selectable.find((index) => index > current) ?? selectable[0];
      } else {
        next = [...selectable].reverse().find((index) => index < current) ?? selectable[selectable.length - 1];
      }

      this.setFocusedIndex(next);
    };

    this.cacheTokens();

    this.handler = (e) => {
      const keys = ['j', 'k', 'w', 'b', ' '];
      if (keys.includes(e.key)) {
        e.preventDefault();

        if (e.key === 'w' || e.key === 'b') {
          const now = performance.now();

          if (e.repeat && now - this.lastNavAt[e.key] < this.repeatIntervalMs) {
            return;
          }

          this.lastNavAt[e.key] = now;
          this.moveFocusOptimistically(e.key);
        }

        this.pushEvent('key_nav', { key: e.key === ' ' ? 'space' : e.key });
      }
    };
    window.addEventListener('keydown', this.handler);
  },
  updated() {
    this.cacheTokens();
  },
  destroyed() {
    window.removeEventListener('keydown', this.handler);
  }
};
