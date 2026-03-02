export default {
  mounted() {
    this.contentEl = this.el.querySelector('.llm-popup-content');
    this.responseEl = this.el.querySelector('.llm-popup-response');
    this.loadingEl = this.el.querySelector('.llm-popup-loading');
    this.errorEl = this.el.querySelector('.llm-popup-error');
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

    this.handleEvent('llm_chunk', ({ content }) => {
      this.appendContent(content);
    });

    this.handleEvent('llm_done', () => {
      this.hideLoading();
    });

    this.handleEvent('llm_error', ({ message }) => {
      this.showError(message);
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
    this.responseEl = this.el.querySelector('.llm-popup-response');
    this.loadingEl = this.el.querySelector('.llm-popup-loading');
    this.errorEl = this.el.querySelector('.llm-popup-error');
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

  appendContent(content) {
    if (!this.responseEl) return;

    const textNode = document.createTextNode(content);
    this.responseEl.appendChild(textNode);

    if (this.shouldAutoScroll()) {
      this.scrollToBottom();
    }
  },

  scrollToBottom() {
    if (this.contentEl) {
      this.contentEl.scrollTop = this.contentEl.scrollHeight;
    }
  },

  hideLoading() {
    if (this.loadingEl) {
      this.loadingEl.style.display = 'none';
    }
  },

  showError(message) {
    if (this.errorEl) {
      this.errorEl.textContent = message;
      this.errorEl.style.display = 'block';
    }
    this.hideLoading();
  }
};
