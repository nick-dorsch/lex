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

    this.getNonKnownIndices = () => {
      return this.tokenEls
        .filter((el) => el.dataset.selectable === 'true')
        .filter((el) => el.dataset.tokenStatus !== 'known')
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

      const navPool =
        key === 'W' || key === 'B'
          ? this.getNonKnownIndices()
          : this.getSelectableIndices();

      if (navPool.length === 0) return;

      const current = this.getFocusedIndex();
      let next;

      if (key === 'w' || key === 'W') {
        next = navPool.find((index) => index > current) ?? navPool[0];
      } else {
        next =
          [...navPool].reverse().find((index) => index < current) ?? navPool[navPool.length - 1];
      }

      this.setFocusedIndex(next);
    };

    this.cacheTokens();

    this.isLLMPopupVisible = () => {
      const popup = document.getElementById('llm-popup');
      return popup && popup.offsetParent !== null;
    };

    this.handler = (e) => {
      if (e.metaKey || e.ctrlKey || e.altKey) {
        return;
      }

      const target = e.target;
      if (target && (target.closest('input, textarea, select') || target.isContentEditable)) {
        return;
      }

      const isQuestionMark = e.key === '?' || (e.key === '/' && e.shiftKey);
      const keys = ['j', 'k', 'w', 'b', 'W', 'B', ' '];

      if (keys.includes(e.key) || isQuestionMark) {
        // Skip space key handling when LLM popup is visible (handled by LLMPopup hook)
        if (e.key === ' ' && this.isLLMPopupVisible()) {
          return;
        }

        e.preventDefault();

        if (['w', 'b', 'W', 'B'].includes(e.key)) {
          const navKey = e.key.toLowerCase();
          const now = performance.now();

          if (e.repeat && now - this.lastNavAt[navKey] < this.repeatIntervalMs) {
            return;
          }

          this.lastNavAt[navKey] = now;
          this.moveFocusOptimistically(e.key);
        }

        const key = e.key === ' ' ? 'space' : isQuestionMark ? '?' : e.key;
        this.pushEvent('key_nav', { key });
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
