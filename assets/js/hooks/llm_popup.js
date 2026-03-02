export default {
  mounted() {
    this.contentEl = this.el.querySelector('.llm-popup-content');
    this.lastManualScroll = 0;
    this.scrollThresholdMs = 2000;

    this.handleContentScroll = () => {
      const isAtBottom = this.isScrolledToBottom();
      if (!isAtBottom) {
        this.lastManualScroll = Date.now();
      }
    };

    if (this.contentEl) {
      this.contentEl.addEventListener('scroll', this.handleContentScroll);
    }

    this.handleEvent('llm_chunk', () => {
      if (this.shouldAutoScroll()) {
        this.scrollToBottom();
      }
    });

    this.handleEvent('llm_done', () => {
      if (this.shouldAutoScroll()) {
        this.scrollToBottom();
      }
    });

    this.keyHandler = (e) => {
      if (e.key === ' ' && this.isPopupVisible()) {
        e.preventDefault();
        e.stopPropagation();
        this.pushEvent('dismiss_llm_popup');
      }
    };

    window.addEventListener('keydown', this.keyHandler, true);
  },

  updated() {
    this.contentEl = this.el.querySelector('.llm-popup-content');

    if (this.shouldAutoScroll()) {
      this.scrollToBottom();
    }
  },

  destroyed() {
    if (this.contentEl) {
      this.contentEl.removeEventListener('scroll', this.handleContentScroll);
    }
    window.removeEventListener('keydown', this.keyHandler, true);
  },

  isPopupVisible() {
    return this.el && this.el.offsetParent !== null;
  },

  isScrolledToBottom() {
    if (!this.contentEl) return true;
    const threshold = 10;
    return (
      this.contentEl.scrollHeight -
      this.contentEl.scrollTop -
      this.contentEl.clientHeight <=
      threshold
    );
  },

  shouldAutoScroll() {
    const timeSinceManualScroll = Date.now() - this.lastManualScroll;
    return timeSinceManualScroll > this.scrollThresholdMs;
  },

  scrollToBottom() {
    if (this.contentEl) {
      this.contentEl.scrollTop = this.contentEl.scrollHeight;
    }
  }
};
