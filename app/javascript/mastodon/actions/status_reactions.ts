import {
  apiDeleteStatusReaction,
  apiPutStatusReaction,
} from 'mastodon/api/statuses';
import type { ApiStatusJSON } from 'mastodon/api_types/statuses';
import { createDataLoadingThunk } from 'mastodon/store/typed_functions';

import { importFetchedStatus } from './importer';

interface StatusReactionArgs extends Record<string, unknown> {
  statusId: string;
  name: string;
  domain?: string;
}

export const putStatusReaction = createDataLoadingThunk<
  ApiStatusJSON,
  StatusReactionArgs
>(
  'statusReaction/put',
  ({ statusId, name, domain }: StatusReactionArgs) =>
    apiPutStatusReaction(statusId, name, domain),
  (status, { dispatch, discardLoadData }) => {
    dispatch(importFetchedStatus(status));
    return discardLoadData;
  },
);

export const deleteStatusReaction = createDataLoadingThunk<
  ApiStatusJSON,
  StatusReactionArgs
>(
  'statusReaction/delete',
  ({ statusId, name, domain }: StatusReactionArgs) =>
    apiDeleteStatusReaction(statusId, name, domain),
  (status, { dispatch, discardLoadData }) => {
    dispatch(importFetchedStatus(status));
    return discardLoadData;
  },
);
