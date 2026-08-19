import { useCallback, useRef } from 'react';

import { useIntl } from 'react-intl';

import classNames from 'classnames';

import type { List, Map as ImmutableMap } from 'immutable';

import {
  deleteStatusReaction,
  putStatusReaction,
} from 'mastodon/actions/status_reactions';
import type { ApiStatusReactionJSON } from 'mastodon/api_types/statuses';
import { AnimatedNumber } from 'mastodon/components/animated_number';
import { Emoji } from 'mastodon/components/emoji';
import EmojiPickerDropdown from 'mastodon/features/compose/containers/emoji_picker_dropdown_container';
import { isUnicodeEmoji } from 'mastodon/features/emoji/utils';
import { useIdentity } from 'mastodon/identity_context';
import { useAppDispatch } from 'mastodon/store';

type ReactionMap = ImmutableMap<keyof ApiStatusReactionJSON, unknown>;

const ReactionEmoji: React.FC<{ reaction: ReactionMap }> = ({ reaction }) => {
  const url = reaction.get('url');
  const name = reaction.get('name') as string;

  if (typeof url === 'string') {
    return (
      <img
        className='status-reactions__custom-emoji'
        src={url}
        alt={`:${name}:`}
        draggable={false}
      />
    );
  }

  return <Emoji code={isUnicodeEmoji(name) ? name : `:${name}:`} />;
};

const StatusReactionChip: React.FC<{
  reaction: ReactionMap;
  statusId: string;
}> = ({ reaction, statusId }) => {
  const dispatch = useAppDispatch();
  const { signedIn } = useIdentity();
  const name = reaction.get('name') as string;
  const domain = reaction.get('domain') as string | undefined;
  const me = Boolean(reaction.get('me'));

  const handleClick = useCallback(() => {
    if (me) {
      void dispatch(deleteStatusReaction({ statusId, name, domain }));
    } else {
      void dispatch(putStatusReaction({ statusId, name, domain }));
    }
  }, [dispatch, domain, me, name, statusId]);

  return (
    <button
      type='button'
      className={classNames('status-reactions__chip', { active: me })}
      aria-pressed={me}
      disabled={!signedIn}
      onClick={handleClick}
    >
      <span className='status-reactions__emoji'>
        <ReactionEmoji reaction={reaction} />
      </span>
      <AnimatedNumber value={reaction.get('count') as number} />
    </button>
  );
};

export const StatusReactions: React.FC<{
  status: ImmutableMap<string, unknown>;
}> = ({ status }) => {
  const intl = useIntl();
  const scrollRef = useRef<HTMLDivElement>(null);
  const statusId = status.get('id') as string;
  const reactions = status.get('reactions') as List<ReactionMap> | undefined;

  const handleWheel = useCallback((event: React.WheelEvent) => {
    const element = scrollRef.current;
    if (!element || Math.abs(event.deltaX) >= Math.abs(event.deltaY)) return;

    if (element.scrollWidth > element.clientWidth) {
      element.scrollLeft += event.deltaY;
      event.preventDefault();
    }
  }, []);

  if (!reactions || reactions.size === 0) return null;

  return (
    <div className='status-reactions'>
      <div
        ref={scrollRef}
        className='status-reactions__scroll'
        role='region'
        aria-label={intl.formatMessage({
          id: 'status.reactions.label',
          defaultMessage: 'Reactions',
        })}
        onWheel={handleWheel}
      >
        {reactions.map((reaction) => {
          const name = reaction.get('name') as string;
          const domain = reaction.get('domain') as string | undefined;

          return (
            <StatusReactionChip
              key={`${name}@${domain ?? ''}`}
              reaction={reaction}
              statusId={statusId}
            />
          );
        })}
      </div>
    </div>
  );
};

export const StatusReactionButton: React.FC<{
  status: ImmutableMap<string, unknown>;
}> = ({ status }) => {
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const { signedIn } = useIdentity();
  const statusId = status.get('id') as string;

  const handleEmojiPick = useCallback(
    (emoji: unknown) => {
      if (typeof emoji !== 'object' || emoji === null) return;

      if ('native' in emoji && typeof emoji.native === 'string') {
        void dispatch(putStatusReaction({ statusId, name: emoji.native }));
      } else if ('shortcode' in emoji && typeof emoji.shortcode === 'string') {
        void dispatch(putStatusReaction({ statusId, name: emoji.shortcode }));
      }
    },
    [dispatch, statusId],
  );

  if (!signedIn) return null;

  return (
    <EmojiPickerDropdown
      className='status-reaction-button'
      buttonClassName='status__action-bar__button'
      inverted={false}
      onPickEmoji={handleEmojiPick}
      title={intl.formatMessage({
        id: 'status.reactions.add',
        defaultMessage: 'Add reaction',
      })}
    />
  );
};
