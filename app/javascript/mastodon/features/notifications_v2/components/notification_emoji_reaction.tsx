import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import MoodIcon from '@/material-icons/400-24px/mood.svg?react';
import { Emoji } from 'mastodon/components/emoji';
import { isUnicodeEmoji } from 'mastodon/features/emoji/utils';
import type { NotificationGroupEmojiReaction } from 'mastodon/models/notification_group';

import type { LabelRenderer } from './notification_group_with_status';
import { NotificationGroupWithStatus } from './notification_group_with_status';

const Reaction: React.FC<{
  reaction: NotificationGroupEmojiReaction['reaction'];
}> = ({ reaction }) => {
  if (!reaction) return null;
  if (reaction.url) {
    return (
      <span className='notification-reaction'>
        <img
          className='notification-reaction-emoji'
          src={reaction.url}
          alt={`:${reaction.name}:`}
          title={`:${reaction.name}:`}
        />
      </span>
    );
  }
  return (
    <span className='notification-reaction'>
      <Emoji
        code={
          isUnicodeEmoji(reaction.name) ? reaction.name : `:${reaction.name}:`
        }
      />
    </span>
  );
};

export const NotificationEmojiReaction: React.FC<{
  notification: NotificationGroupEmojiReaction;
  unread: boolean;
}> = ({ notification, unread }) => {
  const labelRenderer = useCallback<LabelRenderer>(
    (displayedName, total) =>
      total === 1 ? (
        <FormattedMessage
          id='notification.emoji_reaction'
          defaultMessage='{name} reacted {reaction} to your post'
          values={{
            name: displayedName,
            reaction: <Reaction reaction={notification.reaction} />,
          }}
        />
      ) : (
        <FormattedMessage
          id='notification.emoji_reaction.name_and_others'
          defaultMessage='{name} and {count, plural, one {# other} other {# others}} reacted {reaction} to your post'
          values={{
            name: displayedName,
            count: total - 1,
            reaction: <Reaction reaction={notification.reaction} />,
          }}
        />
      ),
    [notification.reaction],
  );

  return (
    <NotificationGroupWithStatus
      type='emoji-reaction'
      icon={MoodIcon}
      iconId='smile'
      accountIds={notification.sampleAccountIds}
      statusId={notification.statusId}
      timestamp={notification.latest_page_notification_at}
      count={notification.notifications_count}
      labelRenderer={labelRenderer}
      unread={unread}
    />
  );
};
