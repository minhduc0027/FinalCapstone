/** Resolves built-in pagination; subclass to supply application-specific strategies. */
public virtual with sharing class DbPageStrategyFactory {
  /** @return A pagination executor for the normalized strategy name. */
  public virtual IDbPageStrategy resolve(String strategy) {
    if (strategy == DbPageRequest.OFFSET) {
      return new DbOffsetStrategy();
    }

    if (strategy == DbPageRequest.KEYSET) {
      return new DbKeysetStrategy();
    }

    if (strategy == DbPageRequest.PAGE_CURSOR) {
      return new DbPageCursorStrategy();
    }

    throw new DbQueryException(
      'Unsupported page strategy: ' +
        strategy +
        '. Use queryLocator() for Batch Apex.'
    );
  }
}
